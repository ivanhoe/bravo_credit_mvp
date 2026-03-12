# BravoCredit

BravoCredit is a multi-country credit application MVP built with Phoenix, Oban, and PostgreSQL.

The project implements the full backend flow requested by the technical challenge:
- create a credit application
- fetch provider data asynchronously
- evaluate risk asynchronously
- expose authenticated query and manual state transition APIs
- process incoming provider webhooks with idempotency
- persist domain events and dispatch PostgreSQL-triggered outbox work

## Implemented Scope

Core capabilities currently implemented:
- `BR`, `CO`, `ES`, `IT`, `MX`, and `PT` country configuration through YAML in `config/countries/*.yaml`
- document validation for `CPF`, `CC`, `DNI`, `Codice Fiscale`, `CURP`, and `NIF`
- Railway-style pipelines with structured errors
- `POST /api/applications`
- `GET /api/applications`
- `GET /api/applications/:id`
- `PATCH /api/applications/:id/state`
- `POST /api/webhooks/provider`
- async jobs with Oban for provider fetch, risk evaluation, webhook processing, and outbox dispatch
- append-only `application_events`
- PostgreSQL trigger from `application_events` to `event_outbox`
- JWT authentication and country-scoped authorization

## Stack

- Elixir / Phoenix / Phoenix LiveView
- PostgreSQL
- Ecto
- Oban
- Guardian
- Cloak
- Req
- YAML Elixir

## Assumptions

- The challenge is implemented as a production-sane MVP, not a fully productized lending platform.
- The six countries from the challenge brief are implemented through the same declarative country architecture.
- External banking providers are simulated behind country adapters and webhooks.
- The operations console is meant for reviewers and internal operators; the authenticated JSON API is the primary integration surface.
- `GET /api/applications/:id` returns a safe detail payload: it includes the aggregate snapshot needed for operations, but masks document identifiers and redacts sensitive banking fields.

## Data Model

Main persisted entities:
- `applications`: main aggregate snapshot with encrypted PII, current state, risk fields, and provider-derived metadata.
- `application_events`: append-only audit history for business changes.
- `event_outbox`: asynchronous side effects created by a PostgreSQL trigger on `application_events`.
- `webhook_events`: idempotent record of incoming external callbacks.
- `oban_jobs`: persisted asynchronous work queues managed by Oban.

The source of truth is PostgreSQL. LiveView dashboards re-query persisted state after lightweight PubSub notifications.

## Security Notes

- API authentication uses JWT via Guardian.
- Authorized API reads and manual transitions are scoped by `country_access`.
- Sensitive fields (`full_name`, `document_id`) are encrypted at rest with Cloak.
- Queries avoid searching by raw PII and rely on hashes for deduplication.
- The challenge UI is intentionally simple; for a production rollout, the `/operations` console should be protected with the same authentication model as the API.

## Caching Strategy

The application uses native Elixir **ETS (Erlang Term Storage)** for high-performance caching.
Currently, this is used for validating and caching the Country Configurations loaded from YAML (`config/countries/*.yaml`).
- **Why**: Country configuration rules evaluate extremely frequently and change rarely.
- **Invalidation Strategy**: These configurations are populated at application startup. If a new country or rule is added, the pod is gracefully restarted.

## Quick Start

1. Create and load your environment file.

```bash
cp .env.example .env
set -a
source .env
set +a
```

2. Replace the example secrets in `.env`.

```bash
mix phx.gen.secret
mix phx.gen.secret
```

Use one value for `SECRET_KEY_BASE` and another for `GUARDIAN_SECRET_KEY`.
`CLOAK_KEY` must be exactly 32 bytes.

3. Start PostgreSQL.

```bash
docker compose up -d postgres
```

4. Install dependencies and bootstrap the database.

```bash
mix deps.get
mix ecto.setup
```

5. Start the app.

```bash
mix phx.server
```

The API and UI will be available at `http://localhost:4000`.
The health endpoint is `http://localhost:4000/health`.
The readiness endpoint is `http://localhost:4000/health/ready`.

If you prefer `just`, its recipes load `.env` automatically once the file exists, so `just setup` and `just server` work without re-exporting variables manually.

## Seed Data

The seed script creates:
- `admin@bravo.test` with access to `BR, CO, ES, IT, MX, PT`
- `analyst-mx@bravo.test` with access to `MX`
- `viewer-co@bravo.test` with access to `CO`
- four sample applications in different states

Run it explicitly at any time with:

```bash
mix run priv/repo/seeds.exs
```

To print JWTs for the seeded users:

```bash
mix bravo.seed.tokens
```

To emit shell exports:

```bash
mix bravo.seed.tokens --env
```

## Local Verification Flow

1. Load a seeded token.

```bash
eval "$(mix bravo.seed.tokens --env)"
export TOKEN="$BRAVO_ANALYST_MX_TOKEN"
```

2. Create a new application.

```bash
curl -sS http://localhost:4000/api/applications \
  -H 'content-type: application/json' \
  -d '{
    "country_code": "MX",
    "full_name": "Jane Applicant",
    "document_id": "GODE561231HDFRRN04",
    "amount": "50000.00",
    "monthly_income": "25000.00",
    "metadata": {"channel": "web"}
  }'
```

3. List authorized applications.

```bash
curl -sS http://localhost:4000/api/applications \
  -H "authorization: Bearer $TOKEN"
```

4. Inspect one application.

```bash
curl -sS http://localhost:4000/api/applications/<application-id> \
  -H "authorization: Bearer $TOKEN"
```

5. Manually move an application already in review.

```bash
curl -sS -X PATCH http://localhost:4000/api/applications/<application-id>/state \
  -H "authorization: Bearer $TOKEN" \
  -H 'content-type: application/json' \
  -d '{"state":"approved"}'
```

6. Simulate a provider webhook.

```bash
curl -sS -X POST http://localhost:4000/api/webhooks/provider \
  -H 'content-type: application/json' \
  -H 'x-idempotency-key: evt-ops-001' \
  -d '{
    "application_id": "<application-id>",
    "event_type": "provider.manual_review_requested",
    "reason": "provider requested extra checks"
  }'
```

## Async and Challenge Mapping

Critical jobs are inserted in the same transaction that persists business changes:
- `FetchProviderData`
- `EvaluateRisk`
- `ProcessIncomingWebhook`

The PostgreSQL-native async requirement is implemented separately:
1. insert into `application_events`
2. PostgreSQL trigger inserts a row into `event_outbox`
3. `DispatchOutbox` drains pending rows
4. non-critical side effects are executed from the outbox

## Country State Policies

State transitions are now defined per country in `config/countries/*.yaml` and resolved through `BravoCredit.Applications.StatePolicy`.

Examples:
- `MX`: allows `approved -> cancelled`
- `CO`: keeps a stricter terminal policy, so `approved` is final and `in_review` can only move to `approved` or `rejected`

This keeps the lifecycle extensible without hardcoding business flow in controllers or workers.

## Observability and Runtime Checks

- `GET /health`: shallow container/process health used for liveness.
- `GET /health/ready`: verifies database connectivity plus critical runtime processes (`Cache`, `PubSub`) and is intended for readiness probes.
- `application_events`, `webhook_events`, and `event_outbox` provide an auditable trail for the operations console.
- LiveView screens subscribe to small PubSub notifications and then re-read PostgreSQL instead of treating websockets as the source of truth.

## Docker Workflow

The default Compose flow runs only PostgreSQL for local development:

```bash
docker compose up -d postgres
```

There is also an app container for the full stack runtime:

```bash
docker compose up --build
```

The app container:
- builds a production release
- runs migrations on startup
- starts Phoenix on port `4000`

## Useful Commands

If you use `just`:

```bash
just db-up
just setup
just seed-data
just seed-tokens
just test
just lint
just app-up
```

Without `just`:

```bash
mix test
mix credo --strict
mix run priv/repo/seeds.exs
mix bravo.seed.tokens
```

## Tests

The current suite covers:
- schemas and changesets
- country config loading and validation
- document validation
- rules engine
- create application pipeline
- provider worker and risk worker
- authenticated application endpoints
- PostgreSQL-triggered outbox dispatch
- incoming provider webhook ingestion and processing

Run the full suite with:

```bash
mix test
```

## Project Documentation

- [Architecture v1](docs/ARCHITECTURE.md)
- [Architecture v2](docs/ARCHITECTURE_V2.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
- [Coding Guidelines](docs/CODING_GUIDELINES.md)
- [Railway and Errors](docs/RAILWAY_AND_ERRORS.md)
- [Delivery Checklist](docs/DELIVERY_CHECKLIST.md)

## Scalability and High Volume Data Handling

As requested by the challenge, here is the analysis on how the application handles growing to millions of credit applications:

- **Database Indexes**: Critical queries are backed by specific indexes:
  - `(country_code, status)` on `applications` for filtering the operations dashboard.
  - `(country_code, requested_at desc)` on `applications` for chronological reading.
  - `(document_hash)` on `applications` to quickly detect duplicate documents (avoiding PII search).
  - `(application_id, inserted_at desc)` on `application_events` to retrieve history fast.
- **Partitioning Strategy**: When reaching tens of millions of records, the `applications` and `application_events` tables are designed to be partitioned **by `country_code`**. This ensures data locality and allows isolating high-volume countries from smaller markets.
- **Avoiding Bottlenecks**: Heavy operations like Risk Evaluation and API interactions with External Providers are moved *out* of the synchronous request cycle using Oban (queues). 
- **Archiving**: Closed/Finalized applications (older than 3 years) could be archived by moving their records from the high-throughput operational PostgreSQL to a cold storage solution (like S3) using the `application_events` audit stream as the source of truth for the data lake.

## Kubernetes Deployment (k8s)

Kubernetes manifests are included in the `k8s/` directory to deploy the main components of this solution:
- `k8s/deployment.yaml`: Phoenix/API deployment with `/health/ready` readiness and `/health` liveness.
- `k8s/worker-deployment.yaml`: Dedicated Oban/worker deployment using the same release image with `PHX_SERVER=false`.
- `k8s/service.yaml`: Exposes the pods internally.
- `k8s/ingress.yaml`: Routes external HTTP traffic to the service.
- `k8s/postgres-service.yaml` and `k8s/postgres-statefulset.yaml`: Minimal PostgreSQL backing service for the MVP manifests.
- `k8s/configmap.yaml` & `k8s/secret.yaml`: Manage environment variables and secrets (simulated for the MVP), including `DATABASE_URL`.

These manifests are intentionally minimal for the challenge. In production, PostgreSQL should be managed separately, secrets should come from a secret manager, and app/worker autoscaling should be tuned independently.

## Tradeoffs

This repository is intentionally scoped as a production-sane MVP:
- two countries are implemented well instead of many superficially
- external providers are simulated behind behaviours and adapters
- some outbound side effects are represented by the outbox infrastructure without fully fleshed external integrations
- Kubernetes files demonstrate deployability, but they are not a full production platform blueprint
