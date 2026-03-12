# BravoCredit - Plan de Implementacion

> Plan operativo para implementar el MVP definido en `ARCHITECTURE_V2.md`.
> Objetivo: construir una entrega fuerte para la prueba tecnica, con alcance controlado y orden de ejecucion claro.

---

## 1. Objetivo

Implementar un MVP "production-sane" que cumpla los requisitos del PDF con:

- 2 paises principales: `MX` y `CO`
- API para crear, consultar, listar y actualizar solicitudes
- procesamiento async con `Oban`
- un flujo DB-triggered con `event_outbox` para cumplir `3.7`
- realtime en frontend con `LiveView`
- seguridad, observabilidad y estructura modular

La meta no es construir la version final del producto.
La meta es entregar un sistema pequeno, coherente, extensible y demostrable.

---

## 2. Alcance bloqueado

### Obligatorio

- Phoenix + Postgres + LiveView
- solicitudes de credito para `MX` y `CO`
- config por pais en YAML
- validacion documental y reglas por pais
- provider simulado por pais
- jobs async: provider + risk
- eventos de dominio persistidos
- webhook entrante o saliente integrado al flujo
- vista realtime de solicitudes
- JWT + autorizacion basica
- README, Docker, K8s manifests, Justfile

### Diferido

- ES completo
- backoffice operativo
- circuit breaker distribuido
- particionamiento fisico real
- UI para editar reglas
- observabilidad avanzada

---

## 3. Criterios de exito

Al final del MVP debe existir:

1. `POST /api/applications` crea solicitud y registra job async.
2. `GET /api/applications/:id` devuelve detalle.
3. `GET /api/applications` lista por pais y filtros.
4. `PATCH /api/applications/:id/state` ejecuta transicion valida.
5. `Oban` procesa provider y evaluacion de riesgo.
6. `LiveView` refleja cambios sin refresh.
7. `application_events` permite reconstruir el flujo.
8. Existe al menos un flujo donde una operacion en DB dispara trabajo async via trigger + outbox.
9. El repo tiene tests reales, commits iterativos y tooling de calidad.

---

## 4. Decisiones tecnicas cerradas

### Framework y librerias

- `Phoenix` + `LiveView`
- `Ecto` + `PostgreSQL`
- `Oban`
- `Req`
- `Guardian`
- `Cloak + Cloak.Ecto`
- `Cachex`
- `YamlElixir`
- `Mox`
- `Credo`

### Arquitectura

- path principal de escritura con `Ecto.Multi`
- jobs criticos encolados dentro de la misma transaccion
- `event_outbox` para el requisito `3.7`
- reglas y configuracion por pais en `config/countries/*.yaml`
- `Pipeline.Context` unico para steps
- estados controlados por modulo de state machine

---

## 5. Estructura objetivo del repo

```text
docs/
  ARCHITECTURE.md
  ARCHITECTURE_V2.md
  IMPLEMENTATION_PLAN.md

lib/
  bravo_credit/
    application.ex
    repo.ex
    vault.ex
    cache.ex
    telemetry.ex
    outbox/
    applications/
    accounts/
    countries/
    rules/
    documents/
    banking/
    pipeline/
    pipelines/
    workers/
    webhooks/

  bravo_credit_web/
    endpoint.ex
    router.ex
    controllers/
    plugs/
    live/

config/
  config.exs
  dev.exs
  test.exs
  runtime.exs
  countries/
    mx.yaml
    co.yaml

priv/repo/migrations/
test/
Dockerfile
docker-compose.yml
Justfile
README.md
.formatter.exs
.credo.exs
.editorconfig
.env.example
```

---

## 6. Orden de implementacion

## Fase 0 - Bootstrap del proyecto

### Objetivo

Dejar el repo listo para desarrollar sobre Phoenix sin volver a pensar infraestructura base.

### Tareas

1. Mover los documentos actuales a `docs/`.
2. Scaffold Phoenix en la raiz del repo.
3. Configurar Postgres y `Ecto`.
4. Agregar dependencias:
   - `oban`
   - `guardian`
   - `jose`
   - `cloak_ecto`
   - `req`
   - `cachex`
   - `yaml_elixir`
   - `mox` en `:test`
   - `credo` en `:dev, :test`
5. Crear `.formatter.exs`, `.credo.exs`, `.editorconfig`, `.env.example`.
6. Crear `Justfile`.
7. Configurar `Oban`, `Guardian`, `Cloak`, `Cachex`.

### Entregables

- proyecto compila
- `mix test` corre
- `mix ecto.create` funciona
- `mix phx.server` levanta

### Comando inicial sugerido

Si se hace scaffold en la raiz:

```bash
mix phx.new . --app bravo_credit --module BravoCredit --database postgres --live --binary-id
```

Si Phoenix se queja porque el directorio no esta vacio, primero se normaliza el repo moviendo docs a `docs/` y luego se ejecuta con el minimo de friccion posible.

---

## Fase 1 - Dominio y persistencia

### Objetivo

Construir el modelo de datos y las primitivas de dominio antes de flujos y UI.

### Migrations

1. `create_users`
2. `create_applications`
3. `create_application_events`
4. `create_webhook_events`
5. `create_event_outbox`

### Campos clave

#### `applications`

- `id`, `:binary_id`
- `country_code`, `:string`
- `full_name`, cifrado
- `full_name_hash`, `:string`
- `document_id`, cifrado
- `document_hash`, `:string`
- `document_type`, `:string`
- `amount`, `:decimal`
- `monthly_income`, `:decimal`
- `status`, `:string`
- `risk_status`, `:string`
- `risk_score`, `:integer`
- `banking_info`, `:map`
- `metadata`, `:map`
- `requested_at`, `:utc_datetime_usec`
- `lock_version`, `:integer`, default `1`

#### `application_events`

- `id`, `:binary_id`
- `application_id`
- `event_type`
- `actor`
- `payload`

#### `webhook_events`

- `id`, `:binary_id`
- `source`
- `idempotency_key`
- `event_type`
- `payload`
- `status`
- `application_id`
- `error_code`, `:string`
- `error_message`, `:string`

#### `event_outbox`

- `id`, `:binary_id`
- `aggregate_type`
- `aggregate_id`
- `event_type`
- `payload`
- `status`
- `attempts`
- `next_attempt_at`
- `last_error_code`, `:string`
- `last_error_message`, `:string`
- `last_error_details`, `:map`
- `processed_at`

### Schemas y modulos

- `BravoCredit.Accounts.User`
- `BravoCredit.Applications.Application`
- `BravoCredit.Applications.ApplicationEvent`
- `BravoCredit.Webhooks.WebhookEvent`
- `BravoCredit.Outbox.Event`
- `BravoCredit.Error`
- `BravoCredit.Errors`
- `BravoCredit.Applications.StateMachine`
- `BravoCredit.Applications.Queries`

### Modelo de errores base

Definir desde Fase 1 un contrato unico de errores:

- `code`
- `message`
- `details`
- `http_status`
- `source`
- `step`
- `retryable?`

Catalogo minimo para arrancar:

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

### Entregables

- migrations aplican sin errores
- schemas compilan
- indices criticos creados
- `lock_version` listo para optimistic locking
- contrato de error definido antes de controllers y workers

---

## Fase 2 - Config por pais y motor de reglas

### Objetivo

Hacer que el sistema soporte `MX` y `CO` sin hardcodear reglas de negocio en controladores o contexts.

### Archivos YAML

- `config/countries/mx.yaml`
- `config/countries/co.yaml`

### Modulos

- `BravoCredit.Countries.Loader`
- `BravoCredit.Countries.Validator`
- `BravoCredit.Countries.Registry`
- `BravoCredit.Rules.Engine`
- `BravoCredit.Documents.CURP`
- `BravoCredit.Documents.CC`

### Responsabilidades

#### `Countries.Loader`

- carga YAML al iniciar
- parsea y normaliza estructura

#### `Countries.Validator`

- valida contrato del YAML
- falla fast si la config es invalida

#### `Countries.Registry`

- expone `get!/1`
- resuelve `validator` y `provider.adapter` via registries internos

#### `Rules.Engine`

- ejecuta reglas por `evaluation_phase`
- soporta:
  - `max_amount_to_income_ratio`
  - `min_income`
  - `max_total_debt_to_income_ratio`

### Entregables

- YAML cargado en runtime
- tests de validacion de config
- tests de reglas para `MX` y `CO`

---

## Fase 3 - Pipeline de creacion

### Objetivo

Tener el primer flujo vertical completo y confiable.

### Modulos

- `BravoCredit.Pipeline.Context`
- `BravoCredit.Pipeline.Step`
- `BravoCredit.Pipeline.Runner`
- `BravoCredit.Pipeline.Steps.ValidateParams`
- `BravoCredit.Pipeline.Steps.ResolveCountryConfig`
- `BravoCredit.Pipeline.Steps.ValidateDocument`
- `BravoCredit.Pipeline.Steps.ValidateInitialRules`
- `BravoCredit.Pipeline.Steps.BuildApplicationChangeset`
- `BravoCredit.Pipeline.Steps.PersistApplication`
- `BravoCredit.Pipelines.CreateApplication`

### Reglas del flujo

`POST /api/applications` debe:

1. validar payload
2. resolver config del pais
3. validar documento
4. validar reglas `evaluation_phase: initial`
5. persistir solicitud
6. persistir `application.created`
7. encolar `FetchProviderData`
8. responder sin esperar al provider

### Context contract

El `Pipeline.Context` debe contener como minimo:

- `request_id`
- `actor`
- `raw_params`
- `input`
- `country_config`
- `application`
- `provider_data`
- `decision`
- `events`
- `errors`

### Entregables

- endpoint de create funcionando
- job de provider queda en Oban
- evento `application.created` queda persistido
- steps retornan errores estructurados
- tests unitarios por step
- test de integracion del pipeline de create

---

## Fase 4 - Integracion con providers

### Objetivo

Obtener informacion bancaria por pais de forma simulada pero estructurada.

### Modulos

- `BravoCredit.Banking.Provider`
- `BravoCredit.Banking.Providers.MX`
- `BravoCredit.Banking.Providers.CO`
- `BravoCredit.Banking.Sanitizer`
- `BravoCredit.Workers.FetchProviderData`
- `BravoCredit.Pipelines.FetchProviderData`

### Comportamiento

Cada provider:

- recibe `document_id`
- retorna payload especifico del pais
- normaliza a formato comun

### Datos simulados esperados

#### MX

- `credit_score`
- `total_debt`

#### CO

- `total_debt`
- `credit_history`

### Entregables

- worker Oban funcional
- `banking_info` sanitizado en DB
- evento `application.provider_data_received`
- test con `Mox` para provider behaviour

---

## Fase 5 - Evaluacion de riesgo

### Objetivo

Aplicar reglas que dependen de provider y decidir resultado inicial.

### Modulos

- `BravoCredit.Pipelines.EvaluateRisk`
- `BravoCredit.Workers.EvaluateRisk`
- `BravoCredit.Pipeline.Steps.LoadApplication`
- `BravoCredit.Pipeline.Steps.EvaluateProviderDependentRules`
- `BravoCredit.Pipeline.Steps.CalculateRiskScore`
- `BravoCredit.Pipeline.Steps.PersistRiskDecision`

### Reglas

#### MX

- ratio monto/ingreso mensual
- score puede influir en `in_review`

#### CO

- `total_debt / monthly_income`

### Decision result

- `approved`
- `rejected`
- `in_review`

### Entregables

- worker de riesgo funcional
- evento `application.risk_evaluated`
- transicion de estado persistida o decision guardada
- tests de boundaries y edge cases

---

## Fase 6 - Consulta, listado y cambio de estado

### Objetivo

Cubrir la operacion principal del sistema desde API.

### Endpoints

- `GET /api/applications/:id`
- `GET /api/applications`
- `PATCH /api/applications/:id/state`

### Modulos

- `BravoCreditWeb.ApplicationController`
- `BravoCreditWeb.FallbackController`
- `BravoCredit.Applications`
- `BravoCredit.Applications.Queries`
- `BravoCredit.Pipelines.UpdateApplicationState`
- `BravoCredit.Pipeline.Steps.CheckPermissions`
- `BravoCredit.Pipeline.Steps.ValidateTransition`
- `BravoCredit.Pipeline.Steps.PersistTransition`

### Filtros de listado

- `country`
- `status`
- `date_from`
- `date_to`

### Concurrencia

- usar `optimistic_lock`
- surfacear conflicto cuando dos procesos actualicen la misma solicitud

### Entregables

- endpoints list/get/update
- auth y autorizacion por recurso
- envelope de error estable para toda la API
- mapeo consistente de `BravoCredit.Error` a HTTP status
- tests de transiciones validas e invalidas

---

## Fase 7 - Auth y autorizacion

### Objetivo

Cerrar seguridad minima requerida por la prueba.

### Endpoints

- `POST /api/auth/login`

### Modulos

- `BravoCredit.Accounts`
- `BravoCredit.Accounts.Guardian`
- `BravoCreditWeb.Plugs.Auth`
- `BravoCreditWeb.Plugs.LoadApplication`
- `BravoCreditWeb.Plugs.AuthorizeCountryAccess`

### Politica de roles

- `admin`
- `analyst`
- `viewer`

### Regla clave

Para rutas con `application_id`, la autorizacion debe resolverse contra la solicitud ya cargada, no contra params arbitrarios del request.

### Entregables

- login funcional
- rutas protegidas
- tests de autorizacion por pais y rol

---

## Fase 8 - Webhooks y outbox

### Objetivo

Cumplir `3.7` y `3.8` del PDF de forma limpia.

### Decision

Implementar:

- webhook entrante
- trigger DB -> `event_outbox`
- worker `DispatchOutbox`

### Endpoints

- `POST /api/webhooks/provider`

### Modulos

- `BravoCreditWeb.WebhookController`
- `BravoCredit.Webhooks`
- `BravoCredit.Webhooks.Processor`
- `BravoCredit.Workers.ProcessIncomingWebhook`
- `BravoCredit.Workers.DispatchOutbox`

### Flujo webhook

1. recibe request externo
2. guarda `webhook_events`
3. encola `ProcessIncomingWebhook`
4. el worker actualiza solicitud y crea `application.state_changed`

### Flujo DB-triggered

1. insert en `application_events`
2. trigger inserta `event_outbox`
3. worker procesa outbox
4. dispara side effect no critico

### Entregables

- migration del trigger
- worker del outbox
- idempotencia por `(source, idempotency_key)`
- persistencia de `last_error_code` y `last_error_message`
- retries solo para errores `retryable?`
- tests de duplicate webhook

---

## Fase 9 - Frontend realtime

### Objetivo

Mostrar que el sistema se actualiza en tiempo casi real.

### Vistas minimas

- `DashboardLive`
- `ApplicationLive`
- `ApplicationFormLive`

### Lo que debe mostrar

#### Dashboard

- listado de solicitudes
- filtros por pais y estado
- refresh en tiempo casi real

#### Detalle

- datos principales
- timeline de eventos
- estado actual

#### Formulario

- crear solicitud
- validacion basica

### Broadcasts minimos

- solicitud creada
- provider data recibida
- estado actualizado

### Entregables

- LiveView funcionando
- cambios visibles sin refresh
- demo creacion -> procesamiento -> cambio visual

---

## Fase 10 - Caching, observabilidad e infraestructura

### Objetivo

Cerrar la entrega para evaluacion.

### Caching

- `BravoCredit.Cache`
- cachear detalle de solicitud por `id`
- invalida en write

### Observabilidad

- logs estructurados
- telemetry minima
- `/health`
- `/health/ready`

### Infra

- `Dockerfile`
- `docker-compose.yml`
- `k8s/`
  - `web/deployment.yaml`
  - `web/service.yaml`
  - `worker/deployment.yaml`
  - `postgres/statefulset.yaml`
  - `ingress.yaml`
  - `configmap.yaml`
  - `secret.yaml`

### README

Debe incluir:

- quick start
- arquitectura
- decisiones tecnicas
- modelo de datos
- seguridad
- async + colas
- caching
- escalabilidad
- k8s

### Entregables

- proyecto arranca en local en menos de 5 minutos
- README suficiente para evaluacion

---

## 7. Plan de pruebas

## 7.1 Unit tests

- validadores de documento
- `Countries.Validator`
- `Rules.Engine`
- `StateMachine`
- steps de pipeline
- `Banking.Sanitizer`

## 7.2 Integration tests

- `CreateApplication` pipeline
- worker de provider
- worker de riesgo
- webhook processing
- API list/get/update

## 7.3 LiveView tests

- dashboard renderiza solicitudes
- detalle muestra timeline
- formulario crea solicitud

## 7.4 Edge cases obligatorios

- pais no soportado
- documento invalido
- monto negativo
- ingreso mensual `0`
- webhook duplicado
- transicion invalida
- usuario sin acceso al pais
- provider caido o timeout

---

## 8. Estrategia de commits

Vetter penaliza repos con pocos commits o mensajes pobres.
La implementacion debe construirse en pasos pequenos.

### Secuencia sugerida

1. `feat: scaffold phoenix app with postgres and liveview`
2. `chore: add formatting, credo, editorconfig and env example`
3. `feat: add core schemas and base migrations`
4. `feat: add yaml country loader and validator`
5. `feat: add document validators for mx and co`
6. `feat: add rules engine for initial and provider phases`
7. `feat: add create application pipeline`
8. `feat: persist domain events and oban jobs in create flow`
9. `feat: add banking provider behaviour and mock adapters`
10. `feat: add provider worker and banking info persistence`
11. `feat: add risk evaluation worker and state decisions`
12. `feat: add api endpoints for list get and state update`
13. `feat: add jwt auth and country authorization`
14. `feat: add webhook ingestion and processing flow`
15. `feat: add event outbox and postgres trigger`
16. `feat: add liveview dashboard and application detail`
17. `feat: add cache layer and health endpoints`
18. `feat: add docker and kubernetes manifests`
19. `test: add pipeline, worker and edge case coverage`
20. `docs: add readme and delivery notes`

---

## 9. Linea de corte si el tiempo aprieta

Si hay que recortar, se recorta en este orden:

1. sacar `ES` por completo
2. reducir frontend a dashboard + detalle
3. dejar solo un webhook flow bien hecho
4. simplificar cache a detalle por `id`
5. dejar K8s minimo y README fuerte

### Lo que NO se recorta

- create/list/get/update
- MX y CO
- YAML configs
- Oban
- eventos persistidos
- tests clave
- JWT
- LiveView realtime basico
- outbox + trigger para `3.7`

---

## 10. Riesgos principales

### Riesgo 1

Meter demasiadas features antes de cerrar el flujo vertical principal.

**Mitigacion**:
cerrar primero create -> provider -> risk -> realtime.

### Riesgo 2

Perder tiempo en infraestructura avanzada antes de tener negocio funcionando.

**Mitigacion**:
Docker y K8s van al final.

### Riesgo 3

Inconsistencias entre YAML, rules engine y state machine.

**Mitigacion**:
tests unitarios desde Fase 2 y 3.

### Riesgo 4

Repo con mala senal para el evaluador por falta de tests o commits.

**Mitigacion**:
commit por fase, tests por modulo desde el inicio.

---

## 11. Siguiente paso ejecutable

El siguiente paso concreto no es seguir editando arquitectura.
Es ejecutar **Fase 0** y dejar el proyecto Phoenix compilando con dependencias base y estructura inicial.

Orden inmediato:

1. normalizar repo
2. scaffold Phoenix
3. configurar dependencias base
4. dejar `mix test` verde
5. arrancar Fase 1 con migrations y schemas
