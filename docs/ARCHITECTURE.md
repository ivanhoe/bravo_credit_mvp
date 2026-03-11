# BravoCredit — Documento de Arquitectura

> Sistema multipaís de solicitudes de crédito para la prueba técnica de Bravo.
> Este documento define las decisiones de diseño a nivel Staff Engineer antes de escribir una línea de código.

---

## 1. Visión general

Construir un sistema extensible que permita gestionar solicitudes de crédito en múltiples países (MX, CO, ES como implementación principal), con reglas de negocio, proveedores bancarios y flujos de estado específicos por país.

El sistema debe ser:
- **Extensible**: agregar un país = agregar un módulo, no tocar el core.
- **Resiliente**: si un proveedor bancario se cae, el sistema no se cae.
- **Observable**: saber qué pasó en cualquier flujo async sin adivinar.
- **Seguro**: PII encriptada en DB, no solo oculta en el API.
- **Escalable**: diseñado para millones de registros aunque el MVP tenga 100.

---

## 2. Principio central: Pipeline Pattern (Pipes)

Toda operación de negocio es un **pipeline** — una secuencia de pasos (pipes) donde cada paso es un módulo independiente con una sola responsabilidad. Esto aplica a creación, actualización de estado, procesamiento de webhooks, y cualquier flujo.

### 2.1 El Behaviour — contrato de cada pipe

```elixir
defmodule BravoCredit.Pipeline.Step do
  @moduledoc """
  Contrato que todo step de un pipeline debe implementar.
  Recibe un contexto (map), retorna {:ok, contexto_enriquecido} o {:halt, contexto_con_error}.
  """

  @type context :: map()
  @type result :: {:ok, context()} | {:halt, context()}

  @callback call(context()) :: result()

  @doc "Nombre legible del step (para logs y telemetry)"
  @callback name() :: String.t()
end
```

### 2.2 El Runner — ejecuta la secuencia

```elixir
defmodule BravoCredit.Pipeline.Runner do
  @moduledoc """
  Ejecuta una lista de steps en secuencia.
  Si un step retorna {:halt, ctx}, el pipeline se detiene inmediatamente.
  Emite telemetry para cada step (duración, éxito/fallo).
  """

  require Logger

  def run(steps, initial_context) do
    Enum.reduce_while(steps, {:ok, initial_context}, fn step, {:ok, ctx} ->
      start = System.monotonic_time()

      case step.call(ctx) do
        {:ok, new_ctx} ->
          emit_telemetry(step, :ok, start)
          {:cont, {:ok, new_ctx}}

        {:halt, new_ctx} ->
          emit_telemetry(step, :halt, start)
          Logger.warning("Pipeline halted at #{step.name()}", reason: new_ctx[:error])
          {:halt, {:halt, new_ctx}}
      end
    end)
  end

  defp emit_telemetry(step, status, start) do
    :telemetry.execute(
      [:bravo, :pipeline, :step],
      %{duration: System.monotonic_time() - start},
      %{step: step.name(), status: status}
    )
  end
end
```

### 2.3 Ejemplo concreto: Crear solicitud

```elixir
defmodule BravoCredit.Pipelines.CreateApplication do
  alias BravoCredit.Pipeline.Runner
  alias BravoCredit.Pipeline.Steps

  @steps [
    Steps.ValidateParams,           # valida que los campos requeridos existan
    Steps.ResolveCountry,           # busca el módulo de reglas del país
    Steps.ValidateDocument,          # delega al país: valida CURP/CC/DNI
    Steps.ValidateBusinessRules,     # delega al país: DTI ratio, umbrales, etc
    Steps.BuildChangeset,            # construye el changeset de Ecto
    Steps.Persist,                   # Ecto.Multi: insert app + insert event
    Steps.BroadcastCreated,          # PubSub → LiveView
    Steps.EnqueueAsyncWork           # encola Oban jobs: banking provider, risk
  ]

  def run(params, opts \\ []) do
    context = %{
      params: params,
      current_user: Keyword.get(opts, :current_user),
      steps_completed: [],
      errors: []
    }

    Runner.run(@steps, context)
  end
end
```

### 2.4 Cada step es testeable de forma aislada

```elixir
# test/bravo_credit/pipeline/steps/validate_document_test.exs
defmodule BravoCredit.Pipeline.Steps.ValidateDocumentTest do
  use ExUnit.Case

  alias BravoCredit.Pipeline.Steps.ValidateDocument

  test "CURP válida pasa" do
    ctx = %{params: %{"document_id" => "GARC850101HDFRRL09"}, country_module: BravoCredit.Countries.MX}
    assert {:ok, _ctx} = ValidateDocument.call(ctx)
  end

  test "CURP inválida detiene el pipeline" do
    ctx = %{params: %{"document_id" => "INVALIDO"}, country_module: BravoCredit.Countries.MX}
    assert {:halt, %{error: _}} = ValidateDocument.call(ctx)
  end
end
```

### 2.5 Pipelines por flujo

No solo la creación usa pipes — **todo** es un pipeline:

```
Crear solicitud:
  ValidateParams → ResolveCountry → ValidateDocument → ValidateBusinessRules
  → BuildChangeset → Persist → BroadcastCreated → EnqueueAsyncWork

Actualizar estado:
  ValidateTransition → CheckPermissions → ApplyTransition → Persist
  → EmitStateChanged → BroadcastUpdated → EnqueueSideEffects

Procesar webhook:
  ValidateSignature → CheckIdempotency → ParsePayload → ResolveApplication
  → ApplyWebhookEffect → Persist → BroadcastUpdated

Evaluar riesgo (Oban worker):
  LoadApplication → LoadBankingInfo → CalculateRiskScore → DetermineDecision
  → UpdateApplication → EmitRiskEvaluated → MaybeAutoTransition
```

### 2.6 Steps reutilizables entre pipelines

```
                    ┌──────────┐
  CreateApp ───────►│ Persist  │◄─────── UpdateState
                    └──────────┘
                    ┌──────────────────┐
  CreateApp ───────►│ BroadcastUpdated │◄─────── ProcessWebhook
                    └──────────────────┘
                    ┌────────────────┐
  CreateApp ───────►│ ResolveCountry │◄─────── EvaluateRisk
                    └────────────────┘
```

Los steps son **bloques LEGO** — se componen en diferentes pipelines sin duplicar código.

### 2.7 Steps específicos por país (composición dinámica)

```elixir
defmodule BravoCredit.Pipelines.CreateApplication do
  alias BravoCredit.Pipeline.Steps

  @base_steps [
    Steps.ValidateParams,
    Steps.ResolveCountry,
    Steps.ValidateDocument,
    Steps.ValidateBusinessRules,
  ]

  @finalize_steps [
    Steps.BuildChangeset,
    Steps.Persist,
    Steps.BroadcastCreated,
    Steps.EnqueueAsyncWork,
  ]

  def run(params, opts \\ []) do
    country_code = params["country_code"]
    country_steps = country_specific_steps(country_code)

    steps = @base_steps ++ country_steps ++ @finalize_steps

    Runner.run(steps, %{params: params, current_user: opts[:current_user]})
  end

  # España tiene un step extra: revisar si supera umbral
  defp country_specific_steps("ES"), do: [Steps.ES.CheckHighAmountThreshold]

  # Colombia necesita validar debt ratio del provider
  defp country_specific_steps("CO"), do: [Steps.CO.ValidateDebtRatio]

  # México: step estándar
  defp country_specific_steps(_), do: []
end
```

### 2.8 SOLID mapeado al Pipeline

| Principio | Cómo se aplica |
|---|---|
| **S** — Single Responsibility | Cada step hace exactamente una cosa. `ValidateDocument` solo valida documentos. |
| **O** — Open/Closed | Agregar funcionalidad = agregar un step al array. Los steps existentes no se tocan. |
| **L** — Liskov Substitution | Todo step implementa `Step` behaviour. Son intercambiables en el pipeline. |
| **I** — Interface Segregation | El behaviour tiene solo `call/1` y `name/0`. Mínimo posible. |
| **D** — Dependency Inversion | El Runner depende del behaviour `Step`, no de módulos concretos. Los pipelines son listas de módulos, inyectables. |

### 2.9 Ventajas para la prueba técnica

1. **Extensible**: agregar un país con regla especial = agregar un step + meterlo en el array
2. **Testeable**: cada step se prueba aislado con un contexto fake
3. **Observable**: el Runner emite telemetry por cada step — sabes exactamente dónde falló y cuánto tardó
4. **Debuggeable**: el contexto acumula `steps_completed`, puedes inspeccionar en qué punto quedó
5. **Reusable**: steps como `Persist`, `BroadcastUpdated`, `ResolveCountry` se usan en múltiples pipelines

---

## 3. Stack técnico

| Capa | Tecnología | Justificación |
|---|---|---|
| Backend | **Elixir + Phoenix** | Concurrencia nativa, fault-tolerance, PubSub built-in, LiveView para real-time |
| Base de datos | **PostgreSQL** | LISTEN/NOTIFY nativo, particionamiento, funciones/triggers, Oban lo usa como queue |
| Job queue | **Oban** | Queue sobre PostgreSQL (sin Redis extra), retries, scheduling, uniqueness, cron, telemetry |
| Frontend | **Phoenix LiveView** | Real-time via WebSocket sin infraestructura extra, sin Socket.IO, sin frontend separado |
| Auth | **Guardian + jose** | JWT estándar, integración nativa con Phoenix plugs |
| Caching | **Cachex** | Cache en memoria con TTL, stats, fallback functions, sin dependencia externa |
| Encryption | **Cloak + Cloak.Ecto** | Encriptación transparente de campos PII en DB |
| HTTP Client | **Req** | Para llamadas a banking providers y webhooks salientes |
| Telemetry | **Telemetry + PromEx** | Métricas estructuradas, exportables a Prometheus |
| Testing | **ExUnit + Mox** | Mox para banking providers (behaviours), ExUnit para todo lo demás |
| Deploy | **Docker + K8s** | Dockerfile multi-stage, manifiestos YAML con HPA |
| Task runner | **Justfile** | Más ergonómico que Makefile, comandos como `just run`, `just test`, `just migrate` |

### Dependencias NOT included (y por qué)

- **Redis**: No necesario. Oban usa PG como queue, Cachex es in-memory. Menos infra = menos fallo.
- **Kafka/RabbitMQ**: Overkill para el MVP. PG NOTIFY + Oban cubre el event-driven pattern.
- **Socket.IO**: LiveView ya tiene WebSocket bidireccional. No hay frontend JS separado.
- **Ecto.FSM / Machinery**: La state machine es suficientemente simple para implementarla con guards y un módulo dedicado. Sin dependencia extra.

---

## 3. Países seleccionados

### MX — México
- **Documento**: CURP (18 caracteres, formato regex conocido)
- **Validación**: formato CURP + regla de debt-to-income ratio (monto solicitado no puede superar 4x el ingreso mensual)
- **Provider bancario**: simula API que retorna score crediticio + deuda total

### CO — Colombia
- **Documento**: Cédula de Ciudadanía (CC, 6-10 dígitos numéricos)
- **Validación**: formato CC + debt-to-income ratio considerando deuda total del provider (deuda_total / ingreso_mensual < 0.4)
- **Provider bancario**: simula API que retorna deuda total + historial crediticio

### ES — España
- **Documento**: DNI (8 dígitos + letra de control calculable)
- **Validación**: formato DNI + letra de control + umbral de monto alto (>50,000 EUR marca como `requires_additional_review`)
- **Provider bancario**: simula API que retorna scoring ASNEF + deuda registrada

---

## 4. Modelo de datos

### 4.1 Esquema principal

```
┌──────────────────────────────────┐
│          applications            │
├──────────────────────────────────┤
│ id              uuid PK          │
│ country_code    varchar(2)       │ ── partition key
│ full_name       binary           │ ── encriptado (Cloak)
│ full_name_hash  varchar          │ ── hash para búsquedas
│ document_id     binary           │ ── encriptado (Cloak)
│ document_hash   varchar          │ ── hash para búsquedas
│ document_type   varchar          │ ── "CURP", "CC", "DNI"
│ amount          decimal          │
│ monthly_income  decimal          │
│ status          varchar          │ ── estado actual
│ risk_score      integer          │ ── calculado async
│ banking_info    jsonb            │ ── respuesta del provider (redactada)
│ metadata        jsonb            │ ── datos extra por país
│ requested_at    utc_datetime     │
│ inserted_at     utc_datetime     │
│ updated_at      utc_datetime     │
└──────────────────────────────────┘
        │ 1
        │
        │ N
┌──────────────────────────────────┐
│       application_events         │  ── append-only audit log
├──────────────────────────────────┤
│ id              uuid PK          │
│ application_id  uuid FK          │
│ event_type      varchar          │ ── "created", "state_changed", "risk_evaluated"
│ from_status     varchar          │
│ to_status       varchar          │
│ payload         jsonb            │ ── datos del evento
│ actor           varchar          │ ── "system", "user:uuid", "webhook:provider"
│ inserted_at     utc_datetime     │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│        webhook_events            │  ── idempotency + audit de webhooks
├──────────────────────────────────┤
│ id              uuid PK          │
│ idempotency_key varchar UNIQUE   │
│ source          varchar          │ ── "banking_provider_mx", "external"
│ event_type      varchar          │
│ payload         jsonb            │
│ status          varchar          │ ── "received", "processed", "failed"
│ application_id  uuid FK nullable │
│ inserted_at     utc_datetime     │
│ processed_at    utc_datetime     │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│           users                  │  ── auth básica
├──────────────────────────────────┤
│ id              uuid PK          │
│ email           varchar UNIQUE   │
│ password_hash   varchar          │
│ role            varchar          │ ── "admin", "analyst", "viewer"
│ country_access  varchar[]        │ ── ["MX", "CO"] — autorización por país
│ inserted_at     utc_datetime     │
└──────────────────────────────────┘
```

### 4.2 Relaciones

```
users ──(auth)──► API ──(country_access)──► applications
applications ──(1:N)──► application_events
applications ◄──(webhook)── webhook_events
```

### 4.3 Índices críticos

```sql
-- Queries principales y sus índices
CREATE INDEX idx_applications_country_status ON applications (country_code, status);
CREATE INDEX idx_applications_country_date ON applications (country_code, requested_at DESC);
CREATE INDEX idx_applications_document_hash ON applications (document_hash);
CREATE INDEX idx_applications_status ON applications (status) WHERE status NOT IN ('completed', 'rejected');
-- ^ partial index: solo solicitudes activas, mucho más pequeño

CREATE INDEX idx_app_events_application_id ON application_events (application_id, inserted_at DESC);
CREATE INDEX idx_webhook_events_idempotency ON webhook_events (idempotency_key);
```

### 4.4 Particionamiento (diseño, implementado en migration)

```sql
-- Partición por country_code para escala a millones
CREATE TABLE applications (
  ...
) PARTITION BY LIST (country_code);

CREATE TABLE applications_mx PARTITION OF applications FOR VALUES IN ('MX');
CREATE TABLE applications_co PARTITION OF applications FOR VALUES IN ('CO');
CREATE TABLE applications_es PARTITION OF applications FOR VALUES IN ('ES');
```

**Por qué LIST y no RANGE**: cada país es un tenant lógico, las queries casi siempre filtran por país. LIST garantiza que cada query toca solo una partición.

---

## 5. Event-Driven Architecture

### 5.1 Principio

Toda acción de negocio produce un **domain event**. Los side-effects reaccionan al evento, no viven dentro de la acción principal. Esto permite:
- Agregar side-effects sin tocar el flujo principal
- Retry individual de cada side-effect
- Audit trail automático (los eventos SON el audit log)

### 5.2 Flujo completo de una solicitud (con Pipelines)

```
  POST /api/applications
         │
         ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │  Pipeline: CreateApplication                                    │
  │                                                                 │
  │  ┌──────────────┐   ┌────────────────┐   ┌──────────────────┐ │
  │  │ ValidateParams│──►│ ResolveCountry │──►│ ValidateDocument │ │
  │  └──────────────┘   └────────────────┘   └────────┬─────────┘ │
  │                                                    │           │
  │  ┌──────────────────────┐   ┌───────────────────┐  │           │
  │  │ ValidateBusinessRules│◄──┘  (country steps)  │  │           │
  │  └──────────┬───────────┘   └───────────────────┘  │           │
  │             │                                      │           │
  │  ┌──────────▼──────────┐   ┌──────────────────┐   │           │
  │  │  BuildChangeset     │──►│ Persist (Multi)  │   │           │
  │  │                     │   │  - insert app    │   │           │
  │  │                     │   │  - insert event  │   │           │
  │  └─────────────────────┘   └────────┬─────────┘   │           │
  │                                     │              │           │
  │  ┌──────────────────┐   ┌──────────▼───────────┐  │           │
  │  │ BroadcastCreated │◄──│ EnqueueAsyncWork     │  │           │
  │  │ (PubSub→LiveView)│   │ (Oban jobs)          │  │           │
  │  └──────────────────┘   └──────────────────────┘  │           │
  └─────────────────────────────────────────────────────────────────┘
         │
         │ {:ok, context} con application + events encolados
         │
         ▼
  ┌──────────────────────┐
  │   PG NOTIFY trigger   │◄── trigger en application_events
  │   "new_domain_event"  │
  └──────────┬───────────┘
             │
  ┌──────────┼────────────┐
  ▼          ▼            ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Pipeline: FetchBankingProvider (Oban worker)               │
  │                                                             │
  │  LoadApp → ResolveBankingProvider → CallProvider             │
  │  → SanitizeResponse → UpdateBankingInfo → EmitEvent         │
  └────────────────────────────┬────────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────────┐
  │  Pipeline: EvaluateRisk (Oban worker)                       │
  │                                                             │
  │  LoadApp → LoadBankingInfo → CalculateScore                 │
  │  → DetermineDecision → UpdateRiskScore → EmitEvent          │
  └────────────────────────────┬────────────────────────────────┘
                               │
  ┌────────────────────────────▼────────────────────────────────┐
  │  Pipeline: TransitionState (Oban worker)                    │
  │                                                             │
  │  LoadApp → ValidateTransition → ApplyTransition → Persist   │
  │  → BroadcastUpdated → EnqueueSideEffects                   │
  └────────────────────────────┬────────────────────────────────┘
                               │
                    ┌──────────┼──────────┐
                    ▼          ▼          ▼
                 PubSub    Webhook     Oban:
                (LiveView) (saliente)  Notification
```

**Cada caja es un pipeline. Cada flecha dentro es un step. Todo es composable, testeable, observable.**

### 5.3 Domain events definidos

| Evento | Disparado por | Consumers |
|---|---|---|
| `application.created` | Creación de solicitud | FetchBankingProvider, RiskEvaluation, AuditLog |
| `application.state_changed` | Transición de estado | WebhookNotifier, PubSubBroadcast, ReEvaluation (si aplica) |
| `provider.response_received` | Banking provider responde | UpdateApplication, FraudCheck |
| `risk.evaluated` | Worker de riesgo termina | StateTransition (auto-approve o flag) |
| `webhook.received` | Webhook entrante | ProcessWebhook, AuditLog |

### 5.4 PG Trigger para domain events

```sql
-- Trigger: cada insert en application_events dispara NOTIFY
CREATE OR REPLACE FUNCTION notify_domain_event()
RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify(
    'new_domain_event',
    json_build_object(
      'id', NEW.id,
      'event_type', NEW.event_type,
      'application_id', NEW.application_id
    )::text
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER application_event_notify
AFTER INSERT ON application_events
FOR EACH ROW EXECUTE FUNCTION notify_domain_event();
```

Un `GenServer` listener en Elixir escucha el canal y encola Oban jobs según el `event_type`. Esto cumple el requisito 3.7: "operación en DB genera trabajo async".

---

## 6. Diseño declarativo — Config-driven Country Rules

### 6.1 Principio

Todo lo que varía por país se declara, no se programa. Las reglas de negocio, la validación de documentos, los umbrales, los steps extra del pipeline — todo vive en **configuración**, no en lógica imperativa distribuida en módulos.

Esto significa que:
- Agregar un país = agregar un archivo de config
- Cambiar un umbral = cambiar un número
- Agregar una regla = agregar una entrada a una lista
- En producción: todo esto sería editable desde el backoffice sin deploy

### 6.2 Country Config — la fuente de verdad

Cada país se define declarativamente:

```elixir
# config/countries/mx.exs
%{
  country_code: "MX",
  country_name: "México",
  currency: "MXN",

  # ── Documento ──
  document: %{
    type: "CURP",
    label: "CURP (Clave Única de Registro de Población)",
    format: ~r/^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z\d]{2}$/,
    length: 18,
    # Módulo con validación avanzada (checksum, etc.)
    validator: BravoCredit.Documents.CURP
  },

  # ── Reglas de negocio (evaluadas por el pipeline en orden) ──
  rules: [
    %{type: :max_dti_ratio, params: %{threshold: 4.0},
      message: "El monto solicitado no puede superar 4x el ingreso mensual"},
    %{type: :min_income, params: %{amount: 5_000},
      message: "El ingreso mínimo es $5,000 MXN"},
    %{type: :max_amount, params: %{amount: 500_000},
      message: "El monto máximo es $500,000 MXN"}
  ],

  # ── Pipeline: steps extra que se inyectan después de la validación base ──
  extra_pipeline_steps: [],

  # ── Provider bancario ──
  provider: %{
    module: BravoCredit.Banking.Providers.MX,
    timeout_ms: 5_000,
    circuit_breaker: %{threshold: 3, timeout_ms: 30_000}
  },

  # ── State machine override (nil = usar default) ──
  state_machine: nil,

  # ── Umbral de revisión adicional ──
  additional_review_threshold: Decimal.new("200000")
}
```

```elixir
# config/countries/co.exs
%{
  country_code: "CO",
  country_name: "Colombia",
  currency: "COP",

  document: %{
    type: "CC",
    label: "Cédula de Ciudadanía",
    format: ~r/^\d{6,10}$/,
    length: nil,  # variable
    validator: nil  # solo regex, sin checksum
  },

  rules: [
    %{type: :max_debt_ratio, params: %{threshold: 0.4},
      message: "La deuda total no puede superar 40% del ingreso mensual"},
    %{type: :min_income, params: %{amount: 1_500_000},
      message: "El ingreso mínimo es $1,500,000 COP"}
  ],

  extra_pipeline_steps: ["BravoCredit.Pipeline.Steps.CO.ValidateDebtRatio"],

  provider: %{
    module: BravoCredit.Banking.Providers.CO,
    timeout_ms: 8_000,
    circuit_breaker: %{threshold: 3, timeout_ms: 30_000}
  },

  state_machine: nil,
  additional_review_threshold: nil
}
```

```elixir
# config/countries/es.exs
%{
  country_code: "ES",
  country_name: "España",
  currency: "EUR",

  document: %{
    type: "DNI",
    label: "Documento Nacional de Identidad",
    format: ~r/^\d{8}[A-Z]$/,
    length: 9,
    validator: BravoCredit.Documents.DNI  # valida letra de control
  },

  rules: [
    %{type: :max_dti_ratio, params: %{threshold: 3.5},
      message: "El monto no puede superar 3.5x el ingreso mensual"},
    %{type: :max_amount, params: %{amount: 100_000},
      message: "El monto máximo es €100,000"}
  ],

  extra_pipeline_steps: ["BravoCredit.Pipeline.Steps.ES.CheckHighAmountThreshold"],

  provider: %{
    module: BravoCredit.Banking.Providers.ES,
    timeout_ms: 5_000,
    circuit_breaker: %{threshold: 3, timeout_ms: 30_000}
  },

  state_machine: nil,
  additional_review_threshold: Decimal.new("50000")
}
```

### 6.3 Registry — lee config, no hardcodea módulos

```elixir
defmodule BravoCredit.Countries.Registry do
  @moduledoc """
  Registry config-driven. Lee las definiciones de países de la configuración.
  En el MVP: archivos en config/countries/.
  En producción: leería de base de datos + cache.
  """

  def config_for!(country_code) do
    case configs()[country_code] do
      nil -> raise "Unsupported country: #{country_code}"
      config -> config
    end
  end

  def provider_for!(country_code) do
    config_for!(country_code).provider.module
  end

  def supported_countries do
    configs() |> Map.keys()
  end

  def all_configs do
    configs() |> Map.values()
  end

  # En el MVP: lee de Application config (archivos)
  # En producción: leería de DB con cache en ETS
  defp configs do
    Application.get_env(:bravo_credit, :countries, %{})
  end
end
```

### 6.4 Rule Engine — evalúa reglas declarativas

Las reglas son datos, no código. Un evaluador genérico las ejecuta:

```elixir
defmodule BravoCredit.Rules.Engine do
  @moduledoc """
  Evalúa una lista de reglas declarativas contra los datos de una solicitud.
  Cada regla es un map con :type, :params y :message.
  Agregar un tipo de regla = agregar un clause en evaluate/2.
  """

  def evaluate_all(rules, data) do
    rules
    |> Enum.flat_map(fn rule -> evaluate(rule, data) end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp evaluate(%{type: :max_dti_ratio, params: %{threshold: max}, message: msg}, data) do
    ratio = Decimal.div(data.amount, data.monthly_income)
    if Decimal.gt?(ratio, Decimal.new("#{max}")), do: [msg], else: []
  end

  defp evaluate(%{type: :min_income, params: %{amount: min}, message: msg}, data) do
    if Decimal.lt?(data.monthly_income, Decimal.new("#{min}")), do: [msg], else: []
  end

  defp evaluate(%{type: :max_amount, params: %{amount: max}, message: msg}, data) do
    if Decimal.gt?(data.amount, Decimal.new("#{max}")), do: [msg], else: []
  end

  defp evaluate(%{type: :max_debt_ratio, params: %{threshold: max}, message: msg}, data) do
    case data[:total_debt] do
      nil -> []  # sin dato de deuda, no se puede evaluar aún
      debt ->
        ratio = Decimal.div(debt, data.monthly_income)
        if Decimal.gt?(ratio, Decimal.new("#{max}")), do: [msg], else: []
    end
  end
end
```

### 6.5 El pipeline Step que usa todo esto

```elixir
defmodule BravoCredit.Pipeline.Steps.ValidateDocument do
  @behaviour BravoCredit.Pipeline.Step

  def name, do: "validate_document"

  def call(%{country_config: config, params: params} = ctx) do
    doc = params["document_id"]
    doc_config = config.document

    with :ok <- validate_format(doc, doc_config),
         :ok <- validate_advanced(doc, doc_config) do
      {:ok, ctx}
    else
      {:error, reason} ->
        {:halt, put_in(ctx, [:errors], [%{step: name(), reason: reason} | ctx.errors])}
    end
  end

  # Validación por regex (declarada en config)
  defp validate_format(doc, %{format: regex}) do
    if Regex.match?(regex, doc), do: :ok, else: {:error, :invalid_format}
  end

  # Validación avanzada (módulo declarado en config, opcional)
  defp validate_advanced(_doc, %{validator: nil}), do: :ok
  defp validate_advanced(doc, %{validator: module}), do: module.validate(doc)
end

defmodule BravoCredit.Pipeline.Steps.ValidateBusinessRules do
  @behaviour BravoCredit.Pipeline.Step

  def name, do: "validate_business_rules"

  def call(%{country_config: config, params: params} = ctx) do
    case BravoCredit.Rules.Engine.evaluate_all(config.rules, params) do
      :ok -> {:ok, ctx}
      {:error, messages} ->
        {:halt, put_in(ctx, [:errors], Enum.map(messages, &%{step: name(), reason: &1}))}
    end
  end
end
```

**Nota**: los steps NO saben qué país es. Solo leen `country_config` del contexto. El config declara, el step ejecuta.

### 6.6 Agregar un país nuevo — comparación

```
  ANTES (code-driven)                    AHORA (config-driven)
  ──────────────────────                 ──────────────────────
  1. Crear Countries.BR módulo           1. Crear config/countries/br.exs
  2. Implementar validate_document/1        con document, rules, provider
  3. Implementar validate_application/1  2. (Si doc necesita checksum)
  4. Crear Banking.Providers.BR             crear Documents.CPF
  5. Editar Registry (hardcoded map)     3. Crear Banking.Providers.BR
  6. Recompilar + deploy                 4. Listo

  Cambiar umbral DTI de 4.0 a 3.5:      Cambiar umbral DTI de 4.0 a 3.5:
  1. Abrir Countries.MX                 1. Abrir config/countries/mx.exs
  2. Buscar dónde está el 4.0           2. Cambiar threshold: 3.5
  3. Cambiarlo                           3. Listo
  4. Recompilar + deploy

  Agregar regla nueva para MX:          Agregar regla nueva para MX:
  1. Abrir Countries.MX                 1. Abrir config/countries/mx.exs
  2. Escribir función nueva             2. Agregar a rules: [...]
  3. Integrarla en validate_application    %{type: :nueva_regla, ...}
  4. Recompilar + deploy                3. (Si tipo no existe)
                                            agregar clause en Engine
```

### 6.7 Visión futura: BackOffice como admin de reglas

El paso natural es que estas configs vivan en base de datos y el backoffice permita editarlas:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  BackOffice — Country Rules Manager                          [admin]   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  País: [MX ▼]                                                          │
│                                                                         │
│  ┌─── Documento ──────────────────────────────────────────────────────┐ │
│  │  Tipo: CURP                                                        │ │
│  │  Formato: [A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z\d]{2}                   │ │
│  │  Validador avanzado: BravoCredit.Documents.CURP                   │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─── Reglas de negocio ─────────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  ┌────┐ max_dti_ratio    threshold: [4.0___]  ✏️  🗑️             │ │
│  │  │ ≡  │ "El monto no puede superar 4x el ingreso"                │ │
│  │  └────┘                                                            │ │
│  │  ┌────┐ min_income       amount: [5,000___]   ✏️  🗑️             │ │
│  │  │ ≡  │ "El ingreso mínimo es $5,000 MXN"                        │ │
│  │  └────┘                                                            │ │
│  │  ┌────┐ max_amount       amount: [500,000_]   ✏️  🗑️             │ │
│  │  │ ≡  │ "El monto máximo es $500,000 MXN"                        │ │
│  │  └────┘                                                            │ │
│  │                                                                     │ │
│  │  [+ Agregar regla]                                                 │ │
│  │                                                                     │ │
│  │  Drag & drop (≡) para reordenar. Las reglas se evalúan en orden.  │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─── Pipeline steps extra ──────────────────────────────────────────┐ │
│  │  (ninguno para MX)                     [+ Agregar step]           │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─── Provider ──────────────────────────────────────────────────────┐ │
│  │  Módulo: BravoCredit.Banking.Providers.MX                         │ │
│  │  Timeout: [5000] ms                                               │ │
│  │  Circuit breaker: threshold [3] fallos, timeout [30000] ms        │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│                                    [Guardar]  [Preview cambios]        │
│                                                                         │
│  Último cambio: 2026-03-10 por admin@bravo.com                        │
│  "Se redujo DTI ratio de 4.5 a 4.0 para MX"                          │
└─────────────────────────────────────────────────────────────────────────┘
```

**Para el MVP**: configs en archivos, el backoffice solo muestra (read-only) la configuración actual de cada país.

**Para producción**: configs en DB, el backoffice permite editar + preview + historial de cambios + audit log de quién cambió qué.

La arquitectura no cambia — el Registry lee de una abstracción. Hoy es `Application.get_env`, mañana es `Repo.get + Cachex`.

### 6.8 Banking Provider — Behaviour (se mantiene)

Los providers sí requieren código (cada API es diferente). Pero la config define cuál usar y cómo configurarlo:

```elixir
defmodule BravoCredit.Banking.Provider do
  @doc "Obtiene info bancaria del cliente"
  @callback fetch_client_info(document_id :: String.t(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}

  @doc "Normaliza la respuesta a formato estándar"
  @callback normalize_response(raw_response :: map()) :: map()
end
```

El pipeline resuelve el provider desde config:

```elixir
defmodule BravoCredit.Pipeline.Steps.FetchBankingProvider do
  def call(%{country_config: config, application: app} = ctx) do
    provider = config.provider.module
    timeout = config.provider.timeout_ms

    case provider.fetch_client_info(app.document_id, timeout: timeout) do
      {:ok, raw} ->
        normalized = provider.normalize_response(raw)
        {:ok, %{ctx | banking_info: normalized}}
      {:error, reason} ->
        {:halt, %{ctx | errors: [%{step: name(), reason: reason}]}}
    end
  end
end
```

### 6.9 Resumen — todo es declarativo

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    Declarativo (config)                      │
  │                                                             │
  │  Country config:  qué documento, qué reglas, qué umbrales  │
  │  Pipeline:        qué steps, en qué orden                   │
  │  State machine:   qué transiciones son válidas              │
  │  Oban queues:     cuántos workers por queue                 │
  │  Circuit breaker: cuántos fallos antes de abrir             │
  └──────────────────────────┬──────────────────────────────────┘
                             │
                             │ lee
                             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    Imperativo (código)                       │
  │                                                             │
  │  Pipeline Runner:     ejecuta la secuencia de steps         │
  │  Rule Engine:         evalúa las reglas declaradas          │
  │  State Machine:       aplica las transiciones declaradas    │
  │  Document Validators: valida checksums (CURP, DNI)          │
  │  Banking Providers:   llama APIs externas                   │
  └─────────────────────────────────────────────────────────────┘
                             │
                             │ visible en
                             ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                    BackOffice (UI)                           │
  │                                                             │
  │  MVP:         muestra configs (read-only) + monitor         │
  │  Producción:  edita configs + preview + audit log           │
  └─────────────────────────────────────────────────────────────┘
```

**Agregar un país nuevo**:
1. Crear archivo de config con documento, reglas, umbrales, provider
2. Crear módulo de provider bancario (si es nuevo)
3. (Opcional) Crear validador de documento si tiene checksum
4. Crear migration para partición de tabla

Zero cambios al core. Zero cambios a controllers. Zero cambios al pipeline runner. Zero cambios al rule engine.

---

## 7. State Machine

### 7.1 Estados

```
┌──────────┐    create     ┌───────────┐
│          │──────────────►│  pending   │
│  (none)  │               └─────┬─────┘
└──────────┘                     │
                                 │ banking provider responde
                                 ▼
                          ┌──────────────┐
                          │  evaluating  │◄── risk assessment en curso
                          └──────┬───────┘
                                 │
                    ┌────────────┼────────────┐
                    ▼            ▼            ▼
             ┌───────────┐ ┌─────────┐ ┌──────────┐
             │ approved  │ │rejected │ │in_review │
             └─────┬─────┘ └─────────┘ └────┬─────┘
                   │                        │ revisión manual
                   │                   ┌────┴────┐
                   │                   ▼         ▼
                   │            ┌──────────┐ ┌─────────┐
                   │            │ approved │ │rejected │
                   │            └────┬─────┘ └─────────┘
                   │                 │
                   └────────┬────────┘
                            ▼
                     ┌─────────────┐
                     │  disbursed  │◄── (webhook confirma desembolso)
                     └─────┬───────┘
                           │
                           ▼
                     ┌─────────────┐
                     │  completed  │
                     └─────────────┘

  Cualquier estado activo puede ir a → cancelled (por el usuario o admin)
```

### 7.2 Implementación

```elixir
defmodule BravoCredit.Applications.StateMachine do
  @transitions %{
    "pending"    => ["evaluating", "cancelled"],
    "evaluating" => ["approved", "rejected", "in_review", "cancelled"],
    "in_review"  => ["approved", "rejected", "cancelled"],
    "approved"   => ["disbursed", "cancelled"],
    "disbursed"  => ["completed"],
    "completed"  => [],
    "rejected"   => [],
    "cancelled"  => []
  }

  def can_transition?(from, to) do
    to in Map.get(@transitions, from, [])
  end

  def transition(application, new_status) do
    if can_transition?(application.status, new_status) do
      {:ok, new_status}
    else
      {:error, :invalid_transition,
        "Cannot transition from #{application.status} to #{new_status}"}
    end
  end

  def terminal?(status), do: status in ["completed", "rejected", "cancelled"]
end
```

**Extensibilidad**: países pueden definir transiciones adicionales o restricciones override.

---

## 8. Seguridad

### 8.1 PII Encryption at Rest (Cloak)

```
           App Layer                    DB Layer
    ┌─────────────────┐          ┌─────────────────┐
    │ full_name:       │  write   │ full_name:       │
    │ "Juan Pérez"    │────────►│ 0x7F3A...B2C1   │ ← encriptado
    │                 │          │                 │
    │ document_id:    │  write   │ document_id:    │
    │ "CURP123..."    │────────►│ 0xA1D4...F8E2   │ ← encriptado
    │                 │          │                 │
    │ document_hash:  │  write   │ document_hash:  │
    │ (auto-computed) │────────►│ "sha256:8f14e..." │ ← para queries
    └─────────────────┘          └─────────────────┘
```

- **Vault**: `BravoCredit.Vault` con AES-256-GCM
- **Key rotation**: Cloak soporta múltiples keys, migra automáticamente al leer
- **Búsquedas**: por `document_hash` (SHA-256 con salt), no por el campo encriptado

### 8.2 JWT Auth

```
POST /api/auth/login → {email, password} → JWT token
                                              │
                            ┌─────────────────┤
                            │ Claims:         │
                            │   sub: user_id  │
                            │   role: "admin" │
                            │   countries:    │
                            │     ["MX","CO"] │
                            │   exp: +24h     │
                            └─────────────────┘

Cada request: Authorization: Bearer <token>
  → Plug: verify token
  → Plug: load user
  → Plug: check country_access (user puede ver MX pero no ES)
```

### 8.3 Autorización por país

```elixir
# Plug que restringe acceso por país
defmodule BravoCreditWeb.Plugs.CountryAccess do
  def call(conn, _opts) do
    user = conn.assigns.current_user
    requested_country = conn.params["country_code"] || conn.params["country"]

    if requested_country in user.country_access or "all" in user.country_access do
      conn
    else
      conn |> put_status(403) |> json(%{error: "No access to country #{requested_country}"}) |> halt()
    end
  end
end
```

### 8.4 Redacción de banking_info

La respuesta del provider bancario puede contener datos sensibles. Antes de guardar en `banking_info` (jsonb), se redactan campos sensibles:

```elixir
defmodule BravoCredit.Banking.Sanitizer do
  @redacted_fields ["account_number", "routing_number", "card_number"]

  def sanitize(response) when is_map(response) do
    Map.new(response, fn
      {k, _v} when k in @redacted_fields -> {k, "[REDACTED]"}
      {k, v} when is_map(v) -> {k, sanitize(v)}
      pair -> pair
    end)
  end
end
```

---

## 9. Procesamiento asíncrono

### 9.1 Oban workers

| Worker | Queue | Trigger | Qué hace |
|---|---|---|---|
| `FetchBankingProvider` | `banking` | `application.created` | Llama al provider bancario del país, guarda banking_info |
| `RiskEvaluation` | `risk` | `provider.response_received` | Evalúa riesgo con datos del provider + reglas del país |
| `AuditLogger` | `audit` | Cualquier domain event | Registra en log estructurado (ya existe en `application_events` pero este puede enviar a sistema externo) |
| `WebhookNotifier` | `webhooks` | `application.state_changed` | Envía POST a endpoint externo simulado |
| `StateTransitioner` | `default` | `risk.evaluated` | Transiciona automáticamente según resultado del risk |

### 9.2 PG Listener → Oban dispatcher

```elixir
defmodule BravoCredit.EventListener do
  use GenServer

  # Escucha PG NOTIFY y encola Oban jobs
  def handle_info({:notification, _pid, _ref, "new_domain_event", payload}, state) do
    event = Jason.decode!(payload)

    case event["event_type"] do
      "application.created" ->
        %{application_id: event["application_id"]}
        |> BravoCredit.Workers.FetchBankingProvider.new()
        |> Oban.insert()

      "provider.response_received" ->
        %{application_id: event["application_id"]}
        |> BravoCredit.Workers.RiskEvaluation.new()
        |> Oban.insert()

      "application.state_changed" ->
        %{application_id: event["application_id"]}
        |> BravoCredit.Workers.WebhookNotifier.new()
        |> Oban.insert()

      _ -> :ok
    end

    {:noreply, state}
  end
end
```

Esto cumple el requisito 3.7: **"operación en DB genera trabajo async"**.

### 9.3 Concurrencia

Oban permite configurar concurrencia por queue:

```elixir
config :bravo_credit, Oban,
  queues: [
    default: 10,
    banking: 5,     # max 5 llamadas concurrentes a providers
    risk: 10,
    audit: 20,
    webhooks: 5
  ]
```

Cada queue procesa jobs en paralelo. Escalar = subir el número o agregar nodos.

---

## 10. Circuit Breaker — Resiliencia de providers

### 10.1 Problema

Los banking providers son sistemas externos. Se caen, tienen latencia, rate-limitean.

### 10.2 Solución

```
                    ┌─────────────┐
  fetch_client_info │  Circuit    │
  ─────────────────►│  Breaker    │
                    │             │
                    │ closed ─────┼──► Provider API ──► :ok
                    │             │
                    │ open ───────┼──► {:error, :circuit_open}
                    │             │    (no intenta, falla rápido)
                    │             │
                    │ half_open ──┼──► intenta 1 request
                    │             │    OK → closed / FAIL → open
                    └─────────────┘

  Reglas:
  - 3 fallos consecutivos → open (30s)
  - En open → Oban job se re-encola con backoff exponencial
  - Solicitud queda en status "pending" hasta que el provider responda
```

### 10.3 Implementación

```elixir
defmodule BravoCredit.Banking.CircuitBreaker do
  use GenServer

  # Estado por provider (un circuito por país)
  # %{"MX" => %{status: :closed, failures: 0, last_failure: nil}}

  def call(country_code, fun) do
    GenServer.call(__MODULE__, {:execute, country_code, fun})
  end
end
```

Alternativa: usar librería `Fuse` que ya implementa el patrón.

---

## 11. Webhooks

### 11.1 Webhook entrante (provider confirma desembolso)

```
  External System ──POST /api/webhooks/disbursement──► BravoCredit
                    {
                      "idempotency_key": "disb-uuid-123",
                      "application_id": "uuid",
                      "status": "disbursed",
                      "disbursed_at": "2026-03-11T..."
                    }

  Flujo:
  1. Verificar idempotency_key (¿ya lo procesamos?)
  2. Si es nuevo: insertar en webhook_events, encolar procesamiento
  3. Oban worker: actualiza estado de la solicitud → "disbursed"
  4. Retornar 200 OK inmediatamente (procesamiento es async)
```

### 11.2 Webhook saliente (notificar cambio de estado)

```
  BravoCredit ──POST {configured_url}──► External System
                {
                  "event": "application.state_changed",
                  "application_id": "uuid",
                  "from": "evaluating",
                  "to": "approved",
                  "timestamp": "2026-03-11T..."
                }

  Oban worker con retry (max 3 intentos, backoff exponencial)
```

---

## 12. Caching

### 12.1 Qué se cachea

| Recurso | TTL | Estrategia de invalidación | Por qué |
|---|---|---|---|
| Lista de solicitudes por país | 30s | Invalidar on write (PubSub) | Query más frecuente, filtrada por país |
| Solicitud individual | 60s | Invalidar on update | Detalle se consulta repetidamente |
| Country configs | Infinito (app lifetime) | Reload on update (en producción: invalidar desde backoffice) | Declarativo, cambia poco |
| Banking provider responses | No cachear | N/A | Datos cambian constantemente, deben ser frescos |

### 12.2 Implementación

```elixir
# Cachex con fallback function
def get_application(id) do
  Cachex.fetch(:bravo_cache, "app:#{id}", fn _key ->
    case Repo.get(Application, id) do
      nil -> {:ignore, nil}
      app -> {:commit, app}
    end
  end)
end

# Invalidación vía PubSub
def handle_info({:application_updated, id}, state) do
  Cachex.del(:bravo_cache, "app:#{id}")
  {:noreply, state}
end
```

---

## 13. Real-time — LiveView

### 13.1 Flujo

```
  Browser ◄──WebSocket──► Phoenix LiveView
                              │
                              │ subscribe a PubSub topics:
                              │   "applications:MX"
                              │   "applications:CO"
                              │   "applications:ES"
                              │
                              │ handle_info({:application_updated, app})
                              │   → assign + re-render (automático)
                              │
  Cada cambio de estado, nueva solicitud, o resultado de risk
  se broadcast vía PubSub → LiveView actualiza sin refresh
```

### 13.2 Vistas — App principal

1. **Dashboard**: lista de solicitudes con filtros (país, estado, fecha), updates real-time
2. **Detalle**: datos completos de una solicitud + timeline de eventos
3. **Crear solicitud**: form con validación client-side (LiveView changesets)
4. **Actualizar estado**: botones de transición válida según estado actual

### 13.3 BackOffice — Monitor operativo en tiempo real

Un segundo grupo de LiveViews que consume los mismos PubSub topics y telemetry events que ya existen. No requiere infraestructura adicional — solo vistas nuevas sobre la misma data.

#### Qué muestra

```
┌─────────────────────────────────────────────────────────────────────────┐
│  BackOffice — BravoCredit Operations                          [admin]  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─── Pipeline Monitor (live) ────────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  Solicitud #a1b2  MX  ████████████░░░░  step 5/8  Persist         │ │
│  │  Solicitud #c3d4  CO  ████████████████  completed  320ms          │ │
│  │  Solicitud #e5f6  ES  ████░░░░░░░░░░░░  HALTED    ValidateDoc ❌ │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌─── Métricas por país (hoy) ──────┐  ┌─── Queue Status ───────────┐ │
│  │                                    │  │                             │ │
│  │  MX  ██████████  234 creadas      │  │  banking   ▶ 3 active      │ │
│  │      ██████      142 aprobadas    │  │  risk      ▶ 7 active      │ │
│  │      ██           28 rechazadas   │  │  webhooks  ▶ 1 active      │ │
│  │      ███          64 en review    │  │  audit     ▶ 0 active      │ │
│  │                                    │  │                             │ │
│  │  CO  ████████    189 creadas      │  │  failed:   2 (retry pend.) │ │
│  │      █████       108 aprobadas    │  │  scheduled: 12             │ │
│  │      ███          51 rechazadas   │  │                             │ │
│  │      ██           30 en review    │  │                             │ │
│  │                                    │  │                             │ │
│  │  ES  ██████      156 creadas      │  │                             │ │
│  │      ████         89 aprobadas    │  │                             │ │
│  │      ██           34 rechazadas   │  │                             │ │
│  │      ██           33 en review    │  │                             │ │
│  └────────────────────────────────────┘  └─────────────────────────────┘ │
│                                                                         │
│  ┌─── Circuit Breakers ─────────────┐  ┌─── Alertas recientes ──────┐ │
│  │                                    │  │                             │ │
│  │  MX Provider   🟢 closed          │  │  15:42 ⚠ Provider ES tardó │ │
│  │  CO Provider   🟢 closed          │  │         2.3s (umbral: 1s)  │ │
│  │  ES Provider   🟡 half-open (2/3) │  │  15:38 ❌ Webhook saliente │ │
│  │                                    │  │         timeout endpoint X │ │
│  └────────────────────────────────────┘  │  15:31 ⚠ Risk score MX    │ │
│                                          │         outlier: score 12  │ │
│                                          └─────────────────────────────┘ │
│                                                                         │
│  ┌─── Event Stream (live tail) ───────────────────────────────────────┐ │
│  │                                                                     │ │
│  │  15:44:02  application.created       MX  #a1b2  $50,000 MXN      │ │
│  │  15:44:02  pipeline.step.ok          MX  #a1b2  ValidateParams 2ms│ │
│  │  15:44:03  pipeline.step.ok          MX  #a1b2  ResolveCountry 1ms│ │
│  │  15:44:03  pipeline.step.ok          MX  #a1b2  ValidateDoc   5ms │ │
│  │  15:44:03  provider.response_received CO  #c3d4  score: 720      │ │
│  │  15:44:04  application.state_changed  CO  #c3d4  evaluating→approved│
│  │  15:44:04  webhook.sent              CO  #c3d4  200 OK  145ms    │ │
│  │  15:44:05  pipeline.step.halt        ES  #e5f6  ValidateDoc ❌   │ │
│  │                                                                     │ │
│  └─────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Arquitectura — zero infraestructura nueva

```
  Ya existe (pipeline + workers)          BackOffice (consume lo mismo)
  ┌──────────────────────────┐            ┌──────────────────────────┐
  │ Pipeline Runner          │            │ PipelineMonitorLive      │
  │   :telemetry.execute(    │            │   attach telemetry       │
  │     [:bravo, :pipeline,  │──attach──►│   handler → send to     │
  │      :step], ...)        │            │   LiveView process       │
  │                          │            │                          │
  │ Domain events            │            │ DashboardLive            │
  │   PubSub.broadcast(      │            │   subscribe to           │
  │     "applications:MX",   │──sub────►│   "applications:*"       │
  │     {:created, app})     │            │   "pipeline:*"           │
  │                          │            │   "oban:*"               │
  │ Oban                     │            │                          │
  │   Oban.Telemetry events  │──attach──►│ QueueStatusLive          │
  │   [:oban, :job, :start]  │            │   attach Oban telemetry  │
  │   [:oban, :job, :stop]   │            │                          │
  │   [:oban, :job, :exception]           │ AlertsLive               │
  │                          │            │   subscribe to           │
  │ Circuit Breaker          │            │   "circuit_breaker:*"    │
  │   PubSub.broadcast(      │──sub────►│                          │
  │     "circuit_breaker:ES",│            │ EventStreamLive          │
  │     {:state_changed,...})│            │   subscribe to ALL       │
  └──────────────────────────┘            │   topics (live tail)     │
                                          └──────────────────────────┘
```

#### PubSub topics del BackOffice

| Topic | Eventos | Consumer |
|---|---|---|
| `"applications:{country}"` | created, state_changed, risk_evaluated | DashboardLive, EventStreamLive |
| `"pipeline:{application_id}"` | step.ok, step.halt, pipeline.complete | PipelineMonitorLive |
| `"circuit_breaker:{country}"` | state_changed (closed/open/half_open) | CircuitBreakerLive |
| `"oban:events"` | job started/completed/failed | QueueStatusLive |
| `"backoffice:alerts"` | threshold exceeded, timeout, anomaly | AlertsLive |

#### Implementación del Pipeline Monitor

```elixir
defmodule BravoCreditWeb.BackOffice.PipelineMonitorLive do
  use BravoCreditWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Escucha telemetry de pipelines
      Phoenix.PubSub.subscribe(BravoCredit.PubSub, "pipeline:*")
    end

    {:ok, assign(socket, pipelines: %{})}
  end

  @impl true
  def handle_info({:pipeline_step, %{application_id: id} = event}, socket) do
    pipelines =
      Map.update(socket.assigns.pipelines, id, new_pipeline(event), fn pipeline ->
        update_pipeline(pipeline, event)
      end)

    {:noreply, assign(socket, pipelines: pipelines)}
  end

  defp new_pipeline(event) do
    %{
      application_id: event.application_id,
      country: event.country,
      total_steps: event.total_steps,
      current_step: 1,
      current_step_name: event.step_name,
      status: :running,
      started_at: DateTime.utc_now(),
      steps_completed: []
    }
  end

  defp update_pipeline(pipeline, %{status: :ok} = event) do
    %{pipeline |
      current_step: pipeline.current_step + 1,
      current_step_name: event.step_name,
      steps_completed: pipeline.steps_completed ++ [{event.step_name, event.duration_ms}]
    }
  end

  defp update_pipeline(pipeline, %{status: :halt} = event) do
    %{pipeline | status: :halted, current_step_name: event.step_name}
  end
end
```

#### Alertas automáticas

```elixir
defmodule BravoCredit.BackOffice.AlertManager do
  @moduledoc """
  Escucha telemetry events y genera alertas cuando se superan umbrales.
  No necesita su propio state — es un handler de telemetry puro.
  """

  def setup do
    :telemetry.attach_many("backoffice-alerts", [
      [:bravo, :pipeline, :step],
      [:bravo, :banking, :provider, :request],
      [:oban, :job, :exception]
    ], &handle_event/4, nil)
  end

  # Provider tardó más de 1s
  defp handle_event([:bravo, :banking, :provider, :request], %{duration: d}, meta, _)
       when d > 1_000_000_000 do  # 1s in native units
    broadcast_alert(:warning, "Provider #{meta.country} tardó #{format_duration(d)}")
  end

  # Pipeline step falló
  defp handle_event([:bravo, :pipeline, :step], _measures, %{status: :halt} = meta, _) do
    broadcast_alert(:error, "Pipeline halted en #{meta.step} para #{meta.application_id}")
  end

  # Oban job explotó
  defp handle_event([:oban, :job, :exception], _measures, meta, _) do
    broadcast_alert(:error, "Job #{meta.worker} falló: #{inspect(meta.reason)}")
  end

  defp handle_event(_, _, _, _), do: :ok

  defp broadcast_alert(severity, message) do
    Phoenix.PubSub.broadcast(BravoCredit.PubSub, "backoffice:alerts", {
      :new_alert,
      %{severity: severity, message: message, timestamp: DateTime.utc_now()}
    })
  end
end
```

#### Valor para la evaluación

El backoffice demuestra 3 cosas simultáneamente:
1. **La arquitectura de eventos funciona** — no es teórica, tiene un consumer visible
2. **LiveView brilla** — real-time sin Socket.IO, sin polling, sin infraestructura extra
3. **Pensamiento operativo** — un Staff no solo construye features, piensa en cómo se opera el sistema en producción

El evaluador puede abrir dos pestañas: la app principal y el backoffice. Crea una solicitud en una y ve cómo fluye por el pipeline en la otra. Eso es difícil de olvidar.

---

## 14. Observabilidad

### 14.1 Telemetry events

```elixir
# Emitidos automáticamente:
[:bravo, :application, :created]         # metadata: country, amount_range
[:bravo, :application, :state_changed]   # metadata: from, to, country
[:bravo, :banking, :provider, :request]  # metadata: country, duration, status
[:bravo, :risk, :evaluated]              # metadata: country, score_range, decision
[:bravo, :webhook, :sent]                # metadata: url, status_code, duration
[:bravo, :webhook, :received]            # metadata: source, event_type
```

### 14.2 Structured logging

```elixir
Logger.info("application_created",
  application_id: app.id,
  country: app.country_code,
  amount: app.amount,
  document_type: app.document_type
)
# Output: timestamp=2026-03-11T... level=info msg=application_created application_id=uuid country=MX amount=50000
```

### 14.3 Health endpoints

- `GET /health` → 200 si Phoenix responde (liveness)
- `GET /health/ready` → 200 si DB + Oban están conectados (readiness)

---

## 15. K8s Deployment

### 15.1 Componentes

```
┌─────────────────────────────────────────────────────┐
│  Kubernetes Cluster                                  │
│                                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌────────────┐ │
│  │ web (2-10)  │  │ worker (2-5)│  │ PostgreSQL │ │
│  │ Phoenix     │  │ Oban only   │  │ (StatefulS)│ │
│  │ HPA on CPU  │  │ HPA on queue│  │            │ │
│  └──────┬──────┘  └─────────────┘  └──────┬─────┘ │
│         │                                  │       │
│  ┌──────▼──────┐                          │       │
│  │  Ingress    │                          │       │
│  │ (nginx)     │                          │       │
│  └─────────────┘                          │       │
│                                            │       │
│  ┌─────────────┐                          │       │
│  │ ConfigMap   │ ← env vars no sensibles  │       │
│  │ Secret      │ ← DB password, JWT secret│       │
│  └─────────────┘                          │       │
└─────────────────────────────────────────────────────┘
```

### 15.2 Separación web vs worker

**Misma imagen Docker**, diferente `CMD`:
- Web: `bin/bravo_credit start` (Phoenix endpoint + LiveView)
- Worker: `bin/bravo_credit eval "BravoCredit.Release.start_oban_only()"` (solo procesa jobs)

Esto permite escalar workers independientemente del web.

### 15.3 HPA

- **Web**: escala por CPU (más requests = más pods)
- **Workers**: escala por queue depth (más jobs pendientes = más pods)

### 15.4 Probes

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 4000
  initialDelaySeconds: 10
  periodSeconds: 15

readinessProbe:
  httpGet:
    path: /health/ready
    port: 4000
  initialDelaySeconds: 5
  periodSeconds: 10
```

---

## 16. Estructura del proyecto

```
bravo_credit/
├── lib/
│   ├── bravo_credit/
│   │   ├── application.ex              # Supervision tree
│   │   ├── repo.ex                     # Ecto Repo
│   │   ├── vault.ex                    # Cloak vault (encryption)
│   │   │
│   │   ├── pipeline/                   # ── Pipeline Engine ──
│   │   │   ├── step.ex                 # Behaviour: call/1, name/0
│   │   │   └── runner.ex              # Ejecuta steps en secuencia + telemetry
│   │   │
│   │   ├── pipeline/steps/             # ── Steps reutilizables ──
│   │   │   ├── validate_params.ex
│   │   │   ├── resolve_country.ex
│   │   │   ├── validate_document.ex
│   │   │   ├── validate_business_rules.ex
│   │   │   ├── build_changeset.ex
│   │   │   ├── persist.ex
│   │   │   ├── broadcast_created.ex
│   │   │   ├── broadcast_updated.ex
│   │   │   ├── enqueue_async_work.ex
│   │   │   ├── validate_transition.ex
│   │   │   ├── check_permissions.ex
│   │   │   ├── apply_transition.ex
│   │   │   ├── check_idempotency.ex
│   │   │   ├── es/                     # Steps específicos de España
│   │   │   │   └── check_high_amount_threshold.ex
│   │   │   └── co/                     # Steps específicos de Colombia
│   │   │       └── validate_debt_ratio.ex
│   │   │
│   │   ├── pipelines/                  # ── Pipelines compuestos ──
│   │   │   ├── create_application.ex   # ValidateParams → ... → EnqueueAsyncWork
│   │   │   ├── update_state.ex         # ValidateTransition → ... → EnqueueSideEffects
│   │   │   ├── process_webhook.ex      # CheckIdempotency → ... → BroadcastUpdated
│   │   │   ├── evaluate_risk.ex        # LoadApp → ... → MaybeAutoTransition
│   │   │   └── fetch_banking.ex        # LoadApp → ... → EmitEvent
│   │   │
│   │   ├── applications/               # ── Contexto de negocio ──
│   │   │   ├── credit_application.ex   # Schema Ecto
│   │   │   ├── application_event.ex    # Schema events (audit)
│   │   │   ├── state_machine.ex        # Transiciones
│   │   │   └── queries.ex             # Queries reutilizables (filtros, paginación)
│   │   │
│   │   ├── countries/                  # ── Country Resolution ──
│   │   │   └── registry.ex            # Lee config, resuelve país → config map
│   │   │
│   │   ├── rules/                     # ── Rule Engine ──
│   │   │   └── engine.ex              # Evalúa reglas declarativas del config
│   │   │
│   │   ├── documents/                 # ── Validadores de checksum (solo donde aplica) ──
│   │   │   ├── curp.ex                # México: checksum CURP
│   │   │   └── dni.ex                 # España: letra de control DNI
│   │   │
│   │   ├── banking/                    # ── Providers bancarios ──
│   │   │   ├── provider.ex             # Behaviour
│   │   │   ├── sanitizer.ex            # Redactar datos sensibles
│   │   │   ├── circuit_breaker.ex      # Resiliencia
│   │   │   └── providers/
│   │   │       ├── mx.ex               # Provider MX (simulado)
│   │   │       ├── co.ex               # Provider CO (simulado)
│   │   │       └── es.ex               # Provider ES (simulado)
│   │   │
│   │   ├── workers/                    # ── Oban workers (delegan a pipelines) ──
│   │   │   ├── fetch_banking_provider.ex  # → Pipelines.FetchBanking.run()
│   │   │   ├── risk_evaluation.ex         # → Pipelines.EvaluateRisk.run()
│   │   │   ├── webhook_notifier.ex
│   │   │   └── state_transitioner.ex      # → Pipelines.UpdateState.run()
│   │   │
│   │   ├── webhooks/                   # ── Webhooks ──
│   │   │   ├── webhook_event.ex        # Schema
│   │   │   └── processor.ex            # → Pipelines.ProcessWebhook.run()
│   │   │
│   │   ├── accounts/                   # ── Auth ──
│   │   │   ├── user.ex
│   │   │   └── guardian.ex
│   │   │
│   │   ├── cache.ex                    # Cachex wrapper
│   │   ├── event_listener.ex           # PG LISTEN/NOTIFY → Oban
│   │   └── back_office/
│   │       └── alert_manager.ex        # Telemetry handler → alertas automáticas
│   │
│   └── bravo_credit_web/
│       ├── router.ex
│       ├── plugs/
│       │   ├── auth.ex                 # JWT verification
│       │   └── country_access.ex       # Authorization por país
│       ├── controllers/
│       │   ├── application_controller.ex
│       │   ├── webhook_controller.ex
│       │   └── auth_controller.ex
│       ├── live/
│       │   ├── dashboard_live.ex           # Lista + filtros + real-time
│       │   ├── application_live.ex         # Detalle + timeline
│       │   └── application_form_live.ex    # Crear solicitud
│       │
│       └── live/back_office/               # ── BackOffice Monitor ──
│           ├── overview_live.ex            # Dashboard principal operativo
│           ├── pipeline_monitor_live.ex    # Pipelines en vivo (progress bars)
│           ├── queue_status_live.ex        # Oban queues: active/failed/scheduled
│           ├── circuit_breaker_live.ex     # Estado de providers por país
│           ├── alerts_live.ex              # Alertas en tiempo real
│           └── event_stream_live.ex        # Live tail de todos los eventos
│
├── priv/
│   └── repo/migrations/
│       ├── 001_create_applications.exs  # Con particionamiento
│       ├── 002_create_application_events.exs
│       ├── 003_create_webhook_events.exs
│       ├── 004_create_users.exs
│       └── 005_create_pg_notify_trigger.exs
│
├── k8s/
│   ├── namespace.yaml
│   ├── backend/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── hpa.yaml
│   ├── worker/
│   │   ├── deployment.yaml
│   │   └── hpa.yaml
│   ├── postgres/
│   │   ├── statefulset.yaml
│   │   └── service.yaml
│   ├── configmap.yaml
│   └── secrets.yaml
│
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   ├── runtime.exs                     # Runtime config (env vars)
│   └── countries/                      # ── Country configs declarativos ──
│       ├── mx.exs                      # México: CURP, DTI ratio, provider
│       ├── co.exs                      # Colombia: CC, debt ratio, provider
│       └── es.exs                      # España: DNI, umbral alto, provider
│
├── Dockerfile                          # Multi-stage build
├── Justfile                            # just run, just test, just migrate
├── docker-compose.yml                  # Dev environment
└── README.md                           # Todo lo que piden documentado
```

---

## 17. Checklist de requisitos vs implementación

| # | Requisito | Solución | Status |
|---|---|---|---|
| 3.1 | Crear solicitudes | Applications context + Country validation + Multi | |
| 3.2 | Reglas por país | Behaviours: MX (CURP + DTI), CO (CC + debt ratio), ES (DNI + umbral) | |
| 3.3 | Provider bancario | Behaviours + providers simulados + circuit breaker | |
| 3.4 | Estados | StateMachine module con transiciones + hooks | |
| 3.5 | Consultar solicitud | GET /api/applications/:id + cache | |
| 3.6 | Listar solicitudes | GET /api/applications?country=MX&status=pending + paginación | |
| 3.7 | Async + PG triggers | PG NOTIFY trigger → EventListener → Oban jobs | |
| 3.8 | Webhooks | Entrante: POST /api/webhooks + idempotency. Saliente: WebhookNotifier worker | |
| 3.9 | Concurrencia | Oban queues concurrentes, Task.Supervisor, procesos OTP | |
| 3.10 | Real-time frontend | LiveView + PubSub broadcasts | |
| 4.1 | Arquitectura modular | Pipeline pattern + Contexts + Behaviours + Registry | |
| 4.2 | Seguridad | JWT (Guardian) + country_access plug + Cloak encryption + Sanitizer | |
| 4.3 | Observabilidad | Telemetry + structured logging + health endpoints | |
| 4.4 | Reproducibilidad | docker-compose up + README < 5 min | |
| 4.5 | Escalabilidad | Particionamiento + índices + análisis en README | |
| 4.6 | Colas | Oban (PG-backed) + workers documentados | |
| 4.7 | Caching | Cachex + invalidación por PubSub | |
| 4.8 | K8s | Manifiestos: web, worker, PG, ingress, HPA, probes | |
| 5 | Frontend | LiveView: dashboard, detalle, form, real-time updates | |
| 6.4 | Justfile | just run, just test, just migrate, just seed, just deploy | |
| **Extra** | **BackOffice** | **LiveView monitor: pipelines en vivo, queues, circuit breakers, alertas, event stream** | |

---

## 18. Estrategia de entrega — Cómo ganar la evaluación

### 18.1 Contexto: cómo evalúa Jyr

Jyr creó **vetter-cli**, una herramienta de code review con IA para hiring. Evalúa 3 pilares:

| Pilar | Peso | Qué mide |
|---|---|---|
| **Architecture Awareness** | Alto | Estructura, separación de concerns, design patterns, naming, abstracciones |
| **Code Refinement** | Alto | Código limpio, idiomático, SIN boilerplate AI-generated, buenas librerías |
| **Edge Case Coverage** | Alto | Error handling estratégico, tests de edge cases, validación, seguridad |

Clasificación: **≥4.0 promedio = "AI Orchestrator" (PASA)** | ≥3.0 = "Revisión" | <3.0 = "Rechazado"

Señales automáticas que detecta:
- ≤3 commits = **"code dump"** (flag negativo)
- `rescue _ ->` o `catch :error, _ ->` = **"blanket error handling"** (penalizado)
- Sin linter/formatter config = falta de disciplina
- Secrets hardcodeados = flag de seguridad

### 18.2 Estrategia de commits — iterativos, no dump

El repo debe mostrar **desarrollo incremental**. Mínimo 15-20 commits significativos:

```
Día 1 — Fundaciones
──────────────────────────────────────────────────────
  feat: scaffold Phoenix project with PostgreSQL
  feat: add pipeline engine (Step behaviour + Runner)
  feat: add pipeline Context struct with typed fields
  feat(countries): add declarative config for MX, CO, ES
  feat(rules): add config-driven rule engine
  feat(documents): add CURP validator with checksum
  feat(documents): add DNI validator with control letter
  feat: add credit application schema with Cloak encryption
  feat: add application_events schema (audit log)
  feat: add state machine with transition guards
  feat(db): add PG partitioning migration for applications

Día 2 — Async + integrations
──────────────────────────────────────────────────────
  feat: add Oban workers for banking provider + risk evaluation
  feat: add PG NOTIFY trigger + EventListener for async dispatch
  feat(banking): add simulated providers for MX, CO, ES
  feat(banking): add circuit breaker with per-country state
  feat: add webhook endpoint with idempotency
  feat: add JWT auth with Guardian + country_access plug
  feat: add Cachex layer with PubSub invalidation
  test: add pipeline step unit tests
  test: add edge case tests for document validation
  test: add state machine transition tests

Día 3 — Frontend + deploy + polish
──────────────────────────────────────────────────────
  feat: add LiveView dashboard with real-time updates
  feat: add LiveView application form + detail view
  feat: add BackOffice pipeline monitor
  feat: add Dockerfile multi-stage build
  feat: add K8s manifests (web, worker, postgres, HPA)
  feat: add Justfile with run/test/migrate/seed commands
  chore: add .formatter.exs + .credo.exs
  docs: add comprehensive README
  test: add integration tests for full pipeline flow
```

**Regla**: nunca commitear todo de una vez. Cada commit es una unidad lógica con mensaje descriptivo.

### 18.3 Code Refinement — hacer que NO parezca AI-generated

Jyr penaliza explícitamente código que se ve generado por IA sin refinar. Checklist para cada archivo:

**Naming idiomático Elixir:**
```elixir
# MAL — naming genérico / AI-style
def process_data(input_data) do
  result = do_processing(input_data)
  {:ok, result}
end

# BIEN — naming específico, pattern match, pipe
def evaluate_risk(%Context{application: app, banking_info: info} = ctx) do
  app
  |> calculate_dti_ratio(info)
  |> apply_country_threshold(ctx.country_config)
  |> build_risk_result()
end
```

**Pattern matching en vez de condicionales:**
```elixir
# MAL — if/else chain (parece generado)
def transition(app, new_status) do
  if can_transition?(app.status, new_status) do
    {:ok, new_status}
  else
    {:error, :invalid}
  end
end

# BIEN — pattern match + guard (idiomático Elixir)
def transition(%{status: from}, to) when {from, to} in @valid_transitions do
  {:ok, to}
end
def transition(%{status: from}, to) do
  {:error, {:invalid_transition, from, to}}
end
```

**Pipe operators donde fluye naturalmente:**
```elixir
# MAL — variables intermedias innecesarias
def sanitize(response) do
  cleaned = remove_sensitive_fields(response)
  normalized = normalize_keys(cleaned)
  {:ok, normalized}
end

# BIEN — pipe
def sanitize(response) do
  response
  |> remove_sensitive_fields()
  |> normalize_keys()
  |> then(&{:ok, &1})
end
```

**Sin boilerplate innecesario:**
- No dejar `@moduledoc false` en módulos importantes — escribir docs reales
- No dejar funciones generadas que no se usan
- No dejar comentarios tipo `# TODO: implement` o `# Add your code here`

### 18.4 Error handling estratégico

```elixir
# ❌ BLANKET — penalizado por vetter
def fetch_banking_info(doc_id) do
  try do
    provider.fetch(doc_id)
  rescue
    _ -> {:error, :provider_failed}
  end
end

# ✅ STRATEGIC — recompensado
def fetch_banking_info(doc_id) do
  provider.fetch(doc_id)
rescue
  Req.TransportError -> {:error, :provider_unreachable}
  Jason.DecodeError -> {:error, :invalid_provider_response}
  RuntimeError -> {:error, :provider_internal_error}
end
```

```elixir
# ❌ BLANKET — en Ecto
def create_application(params) do
  case Repo.insert(changeset) do
    {:ok, app} -> {:ok, app}
    {:error, _} -> {:error, :insert_failed}  # pierde info del error
  end
end

# ✅ STRATEGIC — preserva el error, maneja casos específicos
def create_application(params) do
  case Repo.insert(changeset) do
    {:ok, app} ->
      {:ok, app}
    {:error, %Ecto.Changeset{errors: [{:document_hash, {"has already been taken", _}}]}} ->
      {:error, :duplicate_document}
    {:error, %Ecto.Changeset{} = changeset} ->
      {:error, {:validation_failed, format_changeset_errors(changeset)}}
  end
end
```

### 18.5 Tests que cubren edge cases

No solo happy path. El test suite debe demostrar que pensaste en los bordes:

```elixir
# ── Document validation ──
describe "CURP validation" do
  test "valid CURP passes" do ...end
  test "CURP with wrong length fails" do ...end
  test "CURP with invalid characters fails" do ...end
  test "CURP with wrong checksum fails" do ...end
  test "empty string fails" do ...end
  test "nil fails" do ...end
end

# ── Business rules ──
describe "DTI ratio rule" do
  test "ratio below threshold passes" do ...end
  test "ratio exactly at threshold passes" do ...end      # boundary
  test "ratio above threshold fails" do ...end
  test "zero income halts with division error" do ...end   # edge case
  test "negative amount fails" do ...end                   # edge case
end

# ── State machine ──
describe "transitions" do
  test "pending → evaluating is valid" do ...end
  test "pending → approved is invalid" do ...end           # skip state
  test "completed → anything is invalid" do ...end         # terminal state
  test "cancelled → anything is invalid" do ...end         # terminal state
  test "same state transition is invalid" do ...end        # self-loop
end

# ── Pipeline ──
describe "CreateApplication pipeline" do
  test "valid MX application succeeds" do ...end
  test "valid CO application succeeds" do ...end
  test "unsupported country halts at ResolveCountry" do ...end
  test "invalid document halts at ValidateDocument" do ...end
  test "context carries error info from halted step" do ...end
  test "all steps appear in steps_completed on success" do ...end
end

# ── Webhooks ──
describe "webhook idempotency" do
  test "first request processes normally" do ...end
  test "duplicate idempotency_key returns existing result" do ...end
  test "missing idempotency_key is rejected" do ...end
end

# ── Circuit breaker ──
describe "circuit breaker" do
  test "closes after successful call" do ...end
  test "opens after N consecutive failures" do ...end
  test "half-open allows one probe request" do ...end
  test "resets to closed on successful probe" do ...end
end
```

### 18.6 Tooling obligatorio

Archivos que deben existir en el repo desde el día 1:

```
.formatter.exs          # Elixir formatter config
.credo.exs              # Credo static analysis config (estricto)
.gitignore              # Ignorar _build, deps, .env, etc
.env.example            # Variables de entorno documentadas (sin secrets reales)
```

Agregar en el Justfile:

```just
# Corre formatter + credo + tests antes de cada push
lint:
  mix format --check-formatted
  mix credo --strict

test:
  mix test

check: lint test
```

### 18.7 README — lo que Jyr quiere ver

El PDF pide documentar en el README. Pero además, vetter valida que el README exista y tenga sustancia. Estructura recomendada:

```markdown
# BravoCredit

## Quick Start (< 5 min)
  docker-compose up
  # o: just setup && just run

## Architecture
  - Pipeline pattern (link a sección)
  - Config-driven country rules
  - Event-driven async processing
  - Diagrama de alto nivel

## Technical Decisions
  - Por qué Elixir/Phoenix
  - Por qué Oban vs RabbitMQ
  - Por qué LiveView vs SPA separado
  - Por qué Config-driven vs hardcoded

## Data Model
  - Schema diagram
  - Partitioning strategy
  - Indexes

## Security
  - PII encryption (Cloak)
  - JWT auth
  - Country-level authorization
  - PII redaction in banking_info

## Scalability Analysis
  - Partitioning by country
  - Index strategy for millions of records
  - Oban queue scaling
  - K8s HPA

## Concurrency & Async
  - Oban workers
  - PG NOTIFY → EventListener
  - Circuit breaker
  - Pipeline telemetry

## Caching
  - Qué se cachea y por qué
  - Invalidación via PubSub

## Future Evolution
  - Parallel pipeline steps
  - Saga/compensation for rollback
  - Config-driven rules in DB (editable from backoffice)
  - Country onboarding without deploys
```

### 18.8 Plan de ejecución por día

```
Día 1 (Fundaciones) — ~8 horas
──────────────────────────────────────────────────────
  Mañana:
    □ Scaffold Phoenix + PostgreSQL + Oban + Guardian + Cachex + Cloak
    □ Pipeline engine: Step behaviour + Runner + Context struct
    □ Country configs declarativos (mx.exs, co.exs, es.exs)
    □ Rule Engine genérico
    □ Document validators (CURP, DNI)

  Tarde:
    □ Application schema + Cloak encrypted fields
    □ ApplicationEvent schema (audit)
    □ State machine
    □ Migrations (partitioning + PG NOTIFY trigger)
    □ Tests: document validation, rules, state machine

  Commits: ~10-12

Día 2 (Async + API + Auth) — ~8 horas
──────────────────────────────────────────────────────
  Mañana:
    □ CreateApplication pipeline (todos los steps)
    □ UpdateState pipeline
    □ Oban workers: FetchBankingProvider, RiskEvaluation, StateTransitioner
    □ EventListener (PG NOTIFY → Oban)
    □ Banking providers simulados + circuit breaker

  Tarde:
    □ API controllers: CRUD + filtros + paginación
    □ JWT auth + country_access plug
    □ Webhook controller + idempotency
    □ WebhookNotifier worker (saliente)
    □ Cachex layer
    □ Tests: pipeline flow, webhooks, auth, edge cases

  Commits: ~10-12

Día 3 (Frontend + Deploy + Polish) — ~8 horas
──────────────────────────────────────────────────────
  Mañana:
    □ LiveView: dashboard + filtros + real-time
    □ LiveView: application detail + event timeline
    □ LiveView: create application form
    □ BackOffice: pipeline monitor + queue status

  Tarde:
    □ Dockerfile multi-stage
    □ docker-compose.yml
    □ K8s manifests (web, worker, postgres, HPA, probes)
    □ Justfile completo
    □ .formatter.exs + .credo.exs
    □ README completo
    □ Revisión final: refinar código, naming, eliminar boilerplate
    □ Run: mix format + mix credo --strict + mix test

  Commits: ~8-10
```

### 18.9 Checklist final antes de entregar

```
Arquitectura (Pilar 1):
  □ Pipeline pattern implementado y usado en todos los flujos
  □ Config-driven country rules (no hardcoded)
  □ Behaviours para banking providers
  □ Separación clara: pipeline/ steps/ pipelines/ countries/ banking/ workers/
  □ Context struct tipado
  □ State machine con transiciones declarativas

Code Refinement (Pilar 2):
  □ mix format --check-formatted pasa
  □ mix credo --strict pasa
  □ Pattern matching en vez de if/else donde aplique
  □ Pipe operators donde fluya naturalmente
  □ Naming específico del dominio (no genérico)
  □ Moduledocs reales en módulos públicos
  □ Sin TODOs, sin código comentado, sin boilerplate sobrante
  □ Revisar cada archivo: ¿se ve como lo escribiría un humano experto?

Edge Cases (Pilar 3):
  □ Error handling estratégico (rescue específico, no blanket)
  □ Tests de happy path + edge cases + boundaries
  □ Document validation: formato + checksum + nil + empty
  □ Business rules: boundary values + zero income + negative amounts
  □ State machine: transiciones inválidas + estados terminales
  □ Webhooks: idempotency duplicada + payload inválido
  □ Pipeline: country no soportado + step que falla
  □ No secrets hardcodeados (.env.example, no .env)

Entrega:
  □ ≥20 commits con mensajes descriptivos
  □ README completo con todas las secciones
  □ docker-compose up funciona en < 5 min
  □ Justfile con run/test/migrate/seed/lint/check
  □ .formatter.exs + .credo.exs presentes
  □ K8s manifests presentes
  □ .gitignore correcto (no _build, no deps, no .env)
```

---

## 19. Supuestos

1. Los banking providers son simulados (no hay API real). Cada provider retorna datos mock con latencia simulada (100-500ms) para demostrar el patrón async.
2. Los montos están en la moneda local de cada país (MXN, COP, EUR). No hay conversión de divisas.
3. Un usuario puede tener acceso a múltiples países pero no necesariamente a todos.
4. El webhook entrante simula la confirmación de desembolso desde un sistema bancario externo.
5. El risk score es un cálculo simplificado basado en debt-to-income ratio y datos del provider. No es un modelo ML real.
6. Para el MVP, la key de encriptación se configura via variable de entorno. En producción se usaría un KMS (AWS KMS, Vault).
7. El particionamiento de tabla se implementa en migration pero Ecto opera transparentemente sobre la tabla padre.
