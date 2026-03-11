# BravoCredit - Arquitectura V2

> Version 2 del documento de arquitectura.
> Objetivo: definir un MVP serio, extensible y defendible para la prueba tecnica, con decisiones "production-sane" y alcance implementable en pocos dias.

---

## 1. Posicionamiento

Esta version reemplaza el enfoque de "plataforma completa" por uno mas pragmatico:

- Mantener una base de arquitectura fuerte.
- Reducir complejidad distribuida innecesaria para el MVP.
- Cumplir de forma explicita los requisitos del PDF.
- Dejar claro que algunas capacidades avanzadas quedan como evolucion natural, no como deuda de diseño.

La meta no es construir todo lo que un sistema fintech global tendria en 12 meses.
La meta es construir un nucleo correcto, extensible y observable que pueda defenderse como arquitectura de produccion razonable.

---

## 2. Alcance del MVP

### Implementacion principal

Se implementaran **dos paises** como alcance base:

- **MX**: CURP + regla de relacion ingreso/monto.
- **CO**: CC + regla basada en deuda total del provider.

### Extension opcional

- **ES** queda diseñado en el modelo, pero no es necesario para cerrar un MVP fuerte.

### Razon

El PDF pide al menos dos paises. Implementar dos bien da mejor resultado que implementar tres a medias.

---

## 3. Principios de diseno

1. **Un solo write path confiable**
   La creacion y actualizacion de solicitudes debe pasar por un flujo transaccional claro.

2. **Configuracion como datos**
   Reglas, thresholds, tipos documentales y providers por pais deben vivir en archivos YAML legibles.

3. **El codigo ejecuta; la configuracion decide**
   YAML define politica. Elixir implementa comportamientos, validadores y adapters.

4. **Async solo donde aporta**
   No todo debe ser event-driven. Lo critico va en transacciones y jobs claros.

5. **Observabilidad por defecto**
   Cada flujo relevante debe dejar rastro en logs, eventos y estado persistido.

6. **Escalabilidad sin complejidad prematura**
   Se disena para crecer, pero no se introduce infraestructura distribuida que no se va a demostrar en la prueba.

---

## 4. Stack tecnico

| Capa | Tecnologia | Decision |
|---|---|---|
| Backend | Elixir + Phoenix | Modelo de concurrencia solido, OTP, ergonomia para pipelines y jobs |
| Frontend | Phoenix LiveView | Realtime sin frontend separado |
| DB | PostgreSQL | Persistencia principal, consultas, triggers y base para Oban |
| Jobs | Oban | Cola durable sin meter Redis en el MVP |
| Auth | Guardian o equivalente JWT | Cumple requisito de autenticacion |
| Encryption | Cloak + Cloak.Ecto | PII cifrada at rest |
| HTTP | Req | Providers y webhooks |
| Cache | Cachex | Cache de lectura puntual |
| Testing | ExUnit + Mox | Unit, integration y mocking de providers |

### Decisiones explicitas

- **No Redis** en el MVP.
- **No circuit breaker distribuido custom** en el MVP.
- **No backoffice operativo completo** en el MVP.
- **No particionamiento fisico obligatorio** en la implementacion inicial.

El README si debe explicar como evolucionaria el sistema a particiones, cache distribuido y despliegue multi-instancia.

---

## 5. Configuracion por pais en YAML

### Opinion y decision

Usar YAML para reglas y configuracion por pais es una mejor decision para este reto que meter todo en archivos `.exs`, siempre que no intentemos ejecutar codigo arbitrario desde YAML.

**Ventajas:**

- Un evaluador no-Elixir puede inspeccionar reglas facilmente.
- Cambiar thresholds o politicas es mas visible.
- Se acerca mas a un modelo de "business-owned configuration".

**Riesgo a evitar:**

- No guardar nombres de modulos Elixir en YAML.
- No permitir que YAML "ejecute" cosas.

La solucion correcta es usar **identificadores simbolicos** en YAML y resolverlos en codigo mediante un registry.

### Ejemplo: `config/countries/mx.yaml`

```yaml
country_code: MX
country_name: Mexico
currency: MXN

document:
  type: CURP
  validator: curp

rules:
  - id: amount_income_ratio
    kind: max_amount_to_income_ratio
    evaluation_phase: initial
    threshold: "4.0"
    message: El monto solicitado no puede superar 4x el ingreso mensual

provider:
  adapter: bank_mx
  timeout_ms: 5000

review:
  high_amount_threshold: "200000"
```

### Ejemplo: `config/countries/co.yaml`

```yaml
country_code: CO
country_name: Colombia
currency: COP

document:
  type: CC
  validator: cc_basic

rules:
  - id: min_income
    kind: min_income
    evaluation_phase: initial
    amount: "1500000"
    message: El ingreso minimo es 1,500,000 COP

  - id: debt_income_ratio
    kind: max_total_debt_to_income_ratio
    evaluation_phase: provider
    threshold: "0.4"
    message: La deuda total no puede superar 40% del ingreso mensual

provider:
  adapter: bank_co
  timeout_ms: 8000
```

### Registry en codigo

El runtime carga YAML al iniciar la app y valida que solo existan claves y tipos soportados.

```elixir
validator_registry = %{
  "curp" => BravoCredit.Documents.CURP,
  "cc_basic" => BravoCredit.Documents.CC
}

provider_registry = %{
  "bank_mx" => BravoCredit.Banking.Providers.MX,
  "bank_co" => BravoCredit.Banking.Providers.CO
}
```

### Regla de oro

- **YAML decide**: threshold, tipo de regla, provider, metadata del pais.
- **Elixir implementa**: validadores, adapters, rule evaluators, pipelines.

Eso da legibilidad sin perder seguridad ni control.

### Contrato minimo del YAML

Campos obligatorios por archivo:

- `country_code`
- `country_name`
- `currency`
- `document.type`
- `document.validator`
- `rules`
- `provider.adapter`
- `provider.timeout_ms`

Campos opcionales:

- `review.*`
- `metadata.*`

Contrato de cada regla:

- `id`
- `kind`
- `evaluation_phase`: `initial` o `provider`
- `message`

Segun el `kind`, ademas requiere sus propios parametros:

- `max_amount_to_income_ratio` -> `threshold`
- `min_income` -> `amount`
- `max_total_debt_to_income_ratio` -> `threshold`

### Validacion al arranque

La app debe cargar y validar todos los YAML al iniciar.
Si un archivo esta mal, el sistema debe fallar fast y no arrancar.

Validaciones minimas:

- no hay `country_code` duplicados
- no hay keys desconocidas fuera de `metadata`
- cada `validator` existe en el registry
- cada `provider.adapter` existe en el registry
- cada `kind` de regla es soportado
- cada `evaluation_phase` es valida
- los decimales y montos se pueden parsear

### Regla de seguridad

YAML no puede referenciar modulos arbitrarios, expresiones ni funciones.
Solo ids soportados por el runtime.

---

## 6. Modelo de dominio

### 6.1 Tabla `applications`

Campos principales:

- `id`
- `country_code`
- `full_name` cifrado
- `full_name_hash`
- `document_id` cifrado
- `document_hash`
- `document_type`
- `amount`
- `monthly_income`
- `status`
- `risk_status`
- `risk_score`
- `banking_info` jsonb sanitizado
- `metadata` jsonb
- `requested_at`
- `inserted_at`
- `updated_at`

### 6.2 Tabla `application_events`

Append-only audit log de dominio:

- `application.created`
- `application.provider_data_received`
- `application.risk_evaluated`
- `application.state_changed`
- `webhook.received`

### 6.2.1 Payload minimo de eventos

Todos los eventos deben compartir este shape base:

```json
{
  "event_id": "uuid",
  "event_type": "application.created",
  "application_id": "uuid",
  "country_code": "MX",
  "occurred_at": "2026-03-11T18:30:00Z",
  "actor": "system",
  "payload": {}
}
```

Payloads minimos recomendados:

- `application.created`
  - `status`
  - `amount`
  - `document_type`
- `application.provider_data_received`
  - `provider`
  - `provider_reference`
- `application.risk_evaluated`
  - `risk_score`
  - `decision`
- `application.state_changed`
  - `from`
  - `to`
  - `reason`
- `webhook.received`
  - `source`
  - `external_event_type`

### 6.3 Tabla `webhook_events`

Para idempotencia y trazabilidad:

- `source`
- `idempotency_key`
- `event_type`
- `payload`
- `status`
- `application_id`

**Constraint recomendado**:

- unique index sobre `(source, idempotency_key)`

### 6.4 Tabla `users`

- `email`
- `password_hash`
- `role`
- `country_access`

### 6.5 Indices MVP

```sql
create index idx_applications_country_status
  on applications (country_code, status);

create index idx_applications_country_requested_at
  on applications (country_code, requested_at desc);

create index idx_applications_document_hash
  on applications (document_hash);

create index idx_app_events_application_id_inserted_at
  on application_events (application_id, inserted_at desc);

create unique index idx_webhook_events_source_idempotency
  on webhook_events (source, idempotency_key);
```

### 6.6 Escalabilidad

En el MVP se prioriza una sola tabla bien indexada.
El README debe explicar como evolucionar a particionamiento cuando el volumen lo justifique.

Esto evita amarrar el onboarding de un pais nuevo a una migration de particiones desde el dia 1.

### 6.7 Contrato del `Pipeline.Context`

Para evitar inconsistencias entre steps, el pipeline trabaja sobre un contexto unico y estable.

```elixir
defmodule BravoCredit.Pipeline.Context do
  defstruct request_id: nil,
            actor: nil,
            raw_params: %{},
            input: nil,
            country_config: nil,
            application: nil,
            provider_data: nil,
            decision: nil,
            events: [],
            errors: []
end
```

Reglas del contexto:

- `raw_params` solo se usa en el boundary de entrada
- `ValidateParams` transforma `raw_params` en `input`
- `input` es el shape normalizado con atom keys que usa el dominio
- los rules engines y steps de negocio leen `input`, no `raw_params`
- `application` solo existe despues de persistir
- `provider_data` solo existe despues del worker de integracion
- todos los errores se agregan en `errors` con `step`, `code` y `message`

---

## 7. Flujos principales

## 7.1 Crear solicitud

Pipeline sincronico:

```text
ValidateParams
-> ResolveCountryConfig
-> ValidateDocument
-> ValidateInitialRules
-> BuildChangeset
-> PersistApplication
```

`PersistApplication` usa `Ecto.Multi` para:

1. Insertar `applications`
2. Insertar `application_events` con `application.created`
3. Insertar job Oban `FetchProviderData`

### Resultado del `POST /applications`

La API responde cuando:

- la solicitud ya fue validada
- la fila en `applications` ya existe
- el evento `application.created` ya existe
- el job `FetchProviderData` ya quedo registrado

La API no espera:

- llamada al provider
- calculo de riesgo
- transiciones posteriores

Eso mantiene el request corto y la frontera sync/async completamente clara.

### Que valida este flujo

- Formato del payload
- Documento por pais
- Reglas que no requieren provider

### Que NO valida aqui

- Reglas que dependen de deuda total o score externo

Eso pasa despues de obtener datos del provider.

### Estado inicial

- `status = pending`
- `risk_status = not_started`

El worker de provider mueve la solicitud a `provider_processing` al iniciar trabajo real.

## 7.2 Obtener datos del provider

Worker:

```text
LoadApplication
-> ResolveProviderAdapter
-> FetchProviderData
-> SanitizeProviderPayload
-> PersistProviderData
```

Este flujo:

- actualiza `banking_info`
- genera `application.provider_data_received`
- encola `EvaluateRisk`
- actualiza `risk_status = provider_data_ready`

## 7.3 Evaluacion de riesgo

Worker:

```text
LoadApplication
-> EvaluateProviderDependentRules
-> CalculateRiskScore
-> DecideOutcome
-> PersistRiskResult
```

Aqui si entra la regla de CO basada en `total_debt / monthly_income`.

Resultado esperado:

- si el riesgo pasa, se propone `approved`
- si falla reglas duras, se marca `rejected`
- si requiere analisis adicional, se marca `in_review`

## 7.4 Actualizacion de estado

Pipeline sincronico:

```text
LoadApplication
-> CheckPermissions
-> ValidateTransition
-> PersistTransition
-> BroadcastUpdate
```

### Regla de autorizacion sobre recurso

Para cualquier endpoint con `application_id`:

1. validar JWT
2. cargar la solicitud desde DB
3. verificar que `application.country_code` este en `user.country_access`
4. verificar permiso por rol para la accion
5. solo entonces ejecutar el pipeline

La autorizacion nunca debe decidirse solo con params enviados por el cliente.

---

## 8. Estrategia async

### Decision principal

Los jobs criticos se encolan **dentro de la misma transaccion** donde se persisten los cambios de negocio.

Esto aplica a:

- `FetchProviderData`
- `EvaluateRisk`
- `ProcessIncomingWebhook`

### Por que

Es el camino mas claro y confiable para el MVP.
Si la solicitud existe, el job critico ya quedo registrado.

### Cumplimiento del requisito 3.7 del PDF

Se implementara **al menos un flujo** donde un cambio en base de datos genere trabajo async usando una capacidad nativa de PostgreSQL.

#### Flujo propuesto

1. Insert en `application_events`
2. Trigger PostgreSQL inserta una fila en `event_outbox`
3. Worker `DispatchOutbox` consume `event_outbox`
4. Se encola o ejecuta trabajo no critico, por ejemplo:
   - notificacion saliente
   - proyeccion de auditoria

#### Tabla `event_outbox`

Campos minimos:

- `id`
- `aggregate_type`
- `aggregate_id`
- `event_type`
- `payload`
- `status`
- `attempts`
- `next_attempt_at`
- `last_error`
- `processed_at`
- `inserted_at`

Estados:

- `pending`
- `processing`
- `processed`
- `failed`

#### Politica de reintentos

- maximo 10 intentos
- backoff exponencial simple
- si supera el maximo -> `failed`
- un item `failed` no bloquea el flujo principal
- los consumers del outbox deben ser idempotentes

### Por que asi y no con `LISTEN/NOTIFY` como mecanismo principal

- `LISTEN/NOTIFY` es util, pero no debe ser el backbone de side effects criticos del sistema.
- Un outbox persistido es mas defendible como diseno serio.
- Satisface el requisito del PDF sin meter fragilidad innecesaria.

---

## 9. State machine

Estados base:

```text
pending
provider_processing
evaluating
approved
rejected
in_review
cancelled
```

Transiciones validas:

- `pending -> provider_processing | cancelled`
- `provider_processing -> evaluating | cancelled`
- `evaluating -> approved | rejected | in_review`
- `in_review -> approved | rejected | cancelled`
- `approved -> cancelled`

### Semantica de estados

- `pending`: solicitud creada y persistida, aun sin trabajo externo completado
- `provider_processing`: obteniendo datos bancarios externos
- `evaluating`: evaluando reglas con datos completos
- `in_review`: requiere decision manual o analisis adicional
- `approved`: decision positiva final del MVP
- `rejected`: decision negativa final del MVP
- `cancelled`: cancelada por usuario o por operacion

En el MVP, `approved` y `rejected` son estados finales funcionales.
Si se agrega un flujo de desembolso real, se extendera la maquina con estados posteriores.

### Decision

El estado no se muta con `if` sueltos por el codigo.
Las transiciones viven en un modulo unico y se persisten con validacion transaccional.

### Control de concurrencia

- usar `optimistic_lock` o versionado equivalente
- si dos procesos intentan transicionar al mismo tiempo, uno falla de forma explicita

Esto cubre el requisito de concurrencia sin fingir consistencia magica.

---

## 10. Realtime

Se usara LiveView para mostrar:

- listado de solicitudes
- detalle de solicitud
- cambio de estados casi en tiempo real

### Alcance realista

El MVP solo necesita broadcast de eventos utiles:

- solicitud creada
- provider data recibida
- estado actualizado

No se implementa un backoffice operativo complejo en esta fase.
Si hay tiempo, se puede agregar una vista simple de actividad o timeline.

---

## 11. Seguridad

### 11.1 PII

- `full_name` y `document_id` cifrados con Cloak
- hashes separados para busquedas

### 11.2 Datos bancarios

- `banking_info` se sanitiza antes de persistir
- no se exponen campos sensibles crudos en API

### 11.3 Auth

- JWT para autenticar
- plug de autorizacion por pais y por recurso

### 11.3.1 Politica de roles minima

- `admin`: ver y actualizar solicitudes de los paises permitidos
- `analyst`: ver solicitudes y ejecutar transiciones manuales permitidas
- `viewer`: solo lectura

### 11.4 Regla importante

La autorizacion no debe depender solo de `conn.params["country"]`.
Debe resolverse contra el recurso cargado desde DB cuando la operacion es sobre una solicitud existente.

Para rutas de listado, el filtro por pais debe intersectarse con `user.country_access`.
Para rutas de detalle o update, manda el pais de la solicitud persistida.

---

## 12. Observabilidad

### Logs estructurados

Eventos minimos:

- `application_created`
- `provider_request_started`
- `provider_request_finished`
- `risk_evaluated`
- `application_state_changed`
- `webhook_received`
- `webhook_sent`

### Telemetry

Emitir al menos:

- duracion de llamadas a providers
- jobs Oban completados/fallidos
- transiciones de estado
- errores de webhook
- tiempo total desde `application.created` hasta decision final

### Auditabilidad

`application_events` es la fuente principal para reconstruir el flujo de negocio.

### Lo que no prometemos en el MVP

- trazas distribuidas completas
- analytics operationales avanzados
- monitoreo live de cada step interno del pipeline

El objetivo es tener observabilidad suficiente para explicar claramente que paso, no montar una plataforma completa de observabilidad.

---

## 13. Caching

### Que si cachear

- detalle de solicitud por `id`
- listados filtrados frecuentes, si el tiempo alcanza
- country configs cargadas desde YAML

### Que no cachear

- respuestas del provider
- decisiones de riesgo en proceso

### Invalidacion

- invalidate on write
- TTL corto

El cache es una optimizacion puntual, no una capa central del sistema.

---

## 14. Despliegue y escalabilidad

### MVP deployable

- `web` deployment
- `worker` deployment
- `postgres` statefulset
- config map
- secret
- service
- ingress

### Lo que si se afirma

- Web y workers pueden escalar por separado.
- Oban permite multiples workers en paralelo.
- El modelo puede crecer con indices adecuados.

### Lo que no se afirma en el MVP

- cache distribuido global
- circuit breaker cluster-aware
- consistencia distribuida entre caches locales

Eso se documenta como evolucion posterior.

---

## 15. Estructura del proyecto

```text
lib/
  bravo_credit/
    applications/
    pipeline/
    pipelines/
    countries/
    rules/
    documents/
    banking/
    workers/
    webhooks/
    accounts/
    outbox/

  bravo_credit_web/
    controllers/
    plugs/
    live/

config/
  countries/
    mx.yaml
    co.yaml

priv/repo/migrations/
README.md
```

### Nota

El directorio `countries/` ya no contiene logica por pais.
Contiene carga, validacion y resolucion de configuracion YAML.

---

## 16. Lo que explicitamente queda fuera del MVP

- Backoffice completo de operaciones
- Motor de reglas editable por UI
- Circuit breaker distribuido propio
- Particionamiento fisico implementado
- Monitoreo live de pipelines internos
- Onboarding de paises 100% sin codigo

### Justificacion

Ninguno de esos puntos es malo.
Simplemente no son necesarios para demostrar buen criterio de arquitectura en esta prueba.

### Future evolution

Estas capacidades no se descartan; solo se aplazan:

- particionamiento fisico por pais cuando el volumen lo requiera
- cache distribuido si el despliegue multi-nodo lo exige
- circuit breaker compartido o libreria especializada
- UI de configuracion de reglas por pais
- proyecciones adicionales sobre `application_events`

---

## 17. Roadmap de implementacion

### Fase 1

- scaffolding Phoenix + Postgres + Oban
- schemas y migrations base
- carga de country configs desde YAML
- document validators MX y CO
- create application pipeline

### Fase 2

- workers de provider y risk
- state machine
- list/get/update
- JWT y autorizacion
- realtime LiveView

### Fase 3

- webhook flow
- trigger + outbox para cumplir 3.7
- caching
- k8s manifests
- README final

---

## 18. Resumen ejecutivo

La V2 propone una arquitectura mas sobria:

- **YAML para configuracion visible y mantenible**
- **Elixir para comportamientos ejecutables**
- **Jobs criticos dentro de transacciones**
- **DB-triggered async solo en un flujo acotado y defendible**
- **dos paises bien implementados antes que tres paises superficiales**
- **realtime, seguridad y observabilidad sin inflar el alcance**

Esta version no intenta impresionar por tamano.
Intenta ganar por consistencia.
