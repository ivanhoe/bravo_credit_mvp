# BravoCredit - Railway and Error Handling

> Decision de implementacion para flows de negocio, pipelines, controllers y workers.
> Este proyecto adopta Railway Oriented Programming como patron principal para commands y procesos de dominio.

---

## 1. Decision

En este proyecto:

- los errores esperados se modelan como datos
- las excepciones se reservan para fallos inesperados
- los flujos de negocio se componen con resultados explicitos
- HTTP no traduce errores ad-hoc; usa un boundary comun

Esto reemplaza el estilo de:

- lanzar excepciones para todo
- capturarlas globalmente
- reconstruir semantica de negocio en middleware

---

## 2. Contrato base

Todos los commands, pipelines y steps relevantes deben usar el mismo contrato:

```elixir
{:ok, value}
{:error, %BravoCredit.Error{}}
```

Shape base del error:

```elixir
defmodule BravoCredit.Error do
  @enforce_keys [:code, :message]
  defstruct [:code, :message, :http_status, :source, :step, :retryable?, details: %{}]
end
```

---

## 3. Como se ve un flujo Railway

Ejemplo conceptual para `CreateApplication`:

```elixir
with {:ok, input} <- ValidateParams.call(params),
     {:ok, country_config} <- Countries.get(input.country_code),
     :ok <- Documents.validate(country_config, input.document_id),
     :ok <- Rules.validate_initial(country_config, input),
     {:ok, application} <- Applications.persist(input, actor) do
  {:ok, application}
end
```

Lo importante no es `with` en si mismo.
Lo importante es que cada paso comparte el mismo contrato semantico.

---

## 4. `with` no es Railway

`with` es solo una herramienta sintactica para encadenar matches.

Railway implica:

- un contrato consistente de retorno
- corte temprano en fallo
- propagacion predecible del error
- traduccion centralizada en el boundary

Se puede hacer Railway con `with`, `case` o un runner de steps.

---

## 5. Runner de steps

Para pipelines grandes, el enfoque preferido es una lista de steps y un runner comun:

```elixir
defmodule BravoCredit.Pipeline.Runner do
  def run(ctx, steps) do
    Enum.reduce_while(steps, {:ok, ctx}, fn step, {:ok, acc} ->
      case step.call(acc) do
        {:ok, new_acc} -> {:cont, {:ok, new_acc}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
```

Esto es mejor que un `with` gigante cuando:

- hay muchos pasos
- queremos instrumentation
- queremos testear el flujo completo
- queremos reusar el runner en varios pipelines

---

## 6. Reglas por boundary

### Dominio y commands

- retornan `{:ok, value}` o `{:error, %BravoCredit.Error{}}`
- no levantan excepciones por errores esperados

### Controllers

- usan `with` o llamada directa al command
- delegan errores a `FallbackController`

Ejemplo:

```elixir
def create(conn, params) do
  with {:ok, application} <- BravoCredit.Applications.create(params, conn.assigns.current_user) do
    conn
    |> put_status(:created)
    |> render(:show, application: application)
  end
end
```

### FallbackController

- recibe `{:error, %BravoCredit.Error{}}`
- traduce a HTTP status y envelope JSON
- no inventa semantica de negocio

### LiveView

- no usa `FallbackController`
- maneja `{:error, %BravoCredit.Error{}}` con `case` o `with`
- asigna errores a la UI de forma explicita

### Workers

- llaman commands o pipelines del dominio
- traducen errores segun `retryable?`
- no duplican la clasificacion del error

Regla:

- `retryable? == true` -> retry
- `retryable? == false` -> discard o fail controlado

---

## 7. Cuando usar excepciones

Las excepciones si tienen lugar, pero no como control de flujo normal.

Casos validos:

- configuracion invalida al arrancar
- invariantes rotos
- bugs
- scripts y tests que quieren fallar rapido
- wrappers `!` encima de funciones no-raising

Casos no validos:

- validaciones de request
- not found
- conflicto de estado
- provider timeout
- duplicate webhook

---

## 8. Helper `!`

Si hace falta una variante raising, se implementa sobre la no-raising:

```elixir
def create!(params, actor) do
  case create(params, actor) do
    {:ok, application} -> application
    {:error, error} -> raise BravoCredit.Errors.to_exception(error)
  end
end
```

Pero esta variante debe ser la excepcion, no la base del sistema.

---

## 9. Catalogo minimo de errores

Codigos base del proyecto:

- `validation.invalid_params`
- `country.unsupported`
- `document.invalid_format`
- `rules.initial_rejected`
- `application.duplicate_document`
- `application.not_found`
- `state.invalid_transition`
- `auth.unauthenticated`
- `auth.forbidden_country`
- `provider.unreachable`
- `provider.invalid_response`
- `webhook.duplicate_event`
- `outbox.dispatch_failed`
- `system.internal_error`

Cada error debe declarar, cuando aplique:

- `http_status`
- `source`
- `retryable?`
- `details`

---

## 10. Convenciones de implementacion

### Step contract

```elixir
@callback call(BravoCredit.Pipeline.Context.t()) ::
  {:ok, BravoCredit.Pipeline.Context.t()}
  | {:error, BravoCredit.Error.t()}
```

### Command contract

```elixir
@spec create(map(), User.t()) ::
  {:ok, Application.t()}
  | {:error, BravoCredit.Error.t()}
```

### Query contract

Las queries no necesitan forzarse a Railway si una lectura directa es mas clara.
Ejemplo valido:

```elixir
@spec get_application(Ecto.UUID.t()) :: Application.t() | nil
```

Si el boundary requiere error semantico, el caller traduce `nil` a `application.not_found`.

---

## 11. Que evitar

- `{:error, :invalid}` sin contexto
- strings libres como contrato de error
- `raise` para errores de negocio
- `with` enormes con `else` ilegible
- controllers que construyen JSON de error a mano
- workers que parsean mensajes para decidir retry

---

## 12. Decision para este repo

Adoptamos Railway como patron principal para:

- `CreateApplication`
- `FetchProviderData`
- `EvaluateRisk`
- `UpdateApplicationState`
- `Webhook processing`
- `Outbox dispatch`

No lo forzamos en:

- queries simples de lectura
- transforms triviales
- rendering de LiveView pequeno

La meta es consistencia y claridad, no dogma.
