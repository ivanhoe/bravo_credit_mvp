# BravoCredit - Coding Guidelines

> Guia de estilo para escribir Elixir idiomatico, legible y mantenible en este repositorio.
> Objetivo: que el codigo siga siendo entendible dentro de tres meses sin depender de contexto oral.

---

## 1. Principios

- Priorizar claridad sobre cleverness.
- Preferir contratos estables sobre conveniencia local.
- Modelar dominio con structs y modulos, no con mapas anonimos y strings magicos.
- Hacer explicito que es error esperado y que es fallo inesperado.
- Mantener funciones pequenas, con una responsabilidad clara.

---

## 2. Convenciones base

### Naming

- usar `snake_case` para funciones y variables
- usar `CamelCase` para modulos
- usar sufijo `?` para predicados
- usar sufijo `!` solo para variantes que pueden levantar excepcion de forma intencional

### Shape de datos

- usar `structs` cuando un dato tenga forma estable
- evitar mapas libres para contratos internos importantes
- preferir atoms para estados y categorias internas
- no usar multiples booleans para representar un mismo estado

Ejemplo preferido:

```elixir
%Application{status: :approved}
```

Evitar:

```elixir
%{approved: true, rejected: false}
```

### Return values

- mantener retorno consistente por modulo o boundary
- en dominio y pipelines usar `{:ok, value}` o `{:error, %BravoCredit.Error{}}`
- no mezclar demasiados return types en una misma funcion

---

## 3. Maps, structs y pattern matching

### Acceso assertive

- usar `map.key` cuando la llave debe existir
- usar `map[:key]` solo cuando la llave es opcional o dinamica

Esto reduce `nil` accidentales y deja el contrato mas claro.

### Matching

- usar pattern matching para validar shape y despachar por clausulas
- no meter extracciones complejas en la cabeza de la funcion si afecta legibilidad
- cuando la cabeza empieza a cargar demasiada logica, mover decisiones al cuerpo

---

## 4. `with`, `case` y Railway

### Regla principal

`with` es una herramienta, no una arquitectura.
El patron principal del proyecto es **Railway Oriented Programming** para commands, pipelines y boundaries de negocio.

### Cuando usar `with`

- para flujos lineales de happy path
- cuando todos los pasos comparten contrato de retorno
- cuando el `else` sigue siendo pequeno y comprensible

### Cuando usar `case`

- cuando hay branching real
- cuando varias ramas merecen tratamiento explicito
- cuando el flujo deja de ser lineal

### Cuando usar `Enum.reduce_while`

- para runners de steps
- para ejecutar una lista de modulos o funciones que pueden cortar en error

### Que evitar

- `with` gigantes con 8 o 10 pasos y `else` opaco
- convertir todo a excepciones para no manejar `{:error, ...}`
- mezclar `{:error, atom}` con `{:error, string}` y `{:error, map}`

---

## 5. Manejo de errores

### Errores esperados

Los errores de negocio e integracion esperables deben viajar como datos:

```elixir
{:error, %BravoCredit.Error{}}
```

Ejemplos:

- payload invalido
- pais no soportado
- documento invalido
- transicion de estado invalida
- provider no disponible
- webhook duplicado

### Excepciones

Las excepciones quedan para:

- bugs
- invariantes rotos
- configuracion invalida al arrancar
- casos donde realmente no deberiamos continuar

### Traduccion por boundary

- controllers -> `FallbackController`
- workers -> decidir retry o discard segun `retryable?`
- scripts/tests -> se puede usar `!` o `unwrap!` cuando convenga

---

## 6. Procesos y OTP

- no usar `GenServer` solo para organizar codigo
- usar procesos cuando modelen propiedades de runtime reales:
  - concurrencia
  - aislamiento
  - acceso serializado a recurso compartido
  - supervision
- el dominio vive primero en funciones puras o modulos normales

---

## 7. Documentacion

- todo modulo publico o boundary relevante debe tener `@moduledoc`
- toda funcion publica importante debe tener `@doc`
- incluir ejemplos pequenos donde aporten valor
- usar comentarios solo para explicar decisiones o workarounds, no para narrar codigo obvio

---

## 8. Typespecs

- usar `@type` y `@spec` en boundaries y contratos compartidos
- priorizar specs en:
  - errors
  - pipeline steps
  - public contexts
  - provider behaviours
  - workers

Ejemplo:

```elixir
@spec call(Context.t()) :: {:ok, Context.t()} | {:error, BravoCredit.Error.t()}
```

---

## 9. Proyecto: convenciones concretas

### Commands

- cambian estado o persistencia
- retornan `{:ok, value}` o `{:error, %BravoCredit.Error{}}`

### Queries

- no deben tener side effects
- pueden retornar structs, listas o `nil`
- si la ausencia es error de negocio en el boundary, el caller la convierte a `%BravoCredit.Error{}`

### Pipeline steps

- reciben `Pipeline.Context`
- retornan `{:ok, Pipeline.Context.t()}` o `{:error, BravoCredit.Error.t()}`
- no renderizan HTTP
- no hacen `IO.inspect`

### Workers

- usan servicios o pipelines del dominio
- no duplican reglas de negocio
- deciden retry o discard segun el error estructurado

### Controllers

- extraen params
- invocan command o query
- usan `action_fallback`
- no construyen errores ad-hoc

---

## 10. Calidad automatica

- correr `mix format`
- correr `mix credo --strict`
- mantener tests pequenos y legibles
- preferir nombres de test que expliquen comportamiento, no implementacion

---

## 11. Regla final

Si una pieza de codigo requiere demasiado contexto para entenderse, probablemente necesita:

- mejor nombre
- mejor contrato
- menos branching
- menos shape dinamico
- o un modulo intermedio

La legibilidad no se persigue con comentarios largos.
Se persigue con decisiones de diseno consistentes.
