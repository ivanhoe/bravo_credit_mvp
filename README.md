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
- `MX` and `CO` country configuration through YAML in `config/countries/*.yaml`
- document validation for `CURP` and `CC`
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
- Cachex
- YAML Elixir

## Quick Start

1. Create and load your environment file.

```bash
cp .env.example .env
source .env
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

## Demo Data

The seed script creates:
- `admin@bravo.test` with access to `MX, CO`
- `analyst-mx@bravo.test` with access to `MX`
- `viewer-co@bravo.test` with access to `CO`
- four sample applications in different states

Run it explicitly at any time with:

```bash
mix run priv/repo/seeds.exs
```

To print JWTs for the seeded users:

```bash
mix bravo.demo.tokens
```

To emit shell exports:

```bash
mix bravo.demo.tokens --env
```

## Local Demo Flow

1. Load a demo token.

```bash
eval "$(mix bravo.demo.tokens --env)"
export TOKEN="$BRAVO_ANALYST_MX_TOKEN"
```

2. Create a new application.

```bash
curl -sS http://localhost:4000/api/applications \
  -H 'content-type: application/json' \
  -d '{
    "country_code": "MX",
    "full_name": "Jane Demo",
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
  -H 'x-idempotency-key: evt-demo-001' \
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

## Docker Workflow

The default Compose flow runs only PostgreSQL for local development:

```bash
docker compose up -d postgres
```

There is also an app container for a full demo:

```bash
docker compose --profile app up --build
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
just seed-demo
just demo-tokens
just test
just lint
just app-up
```

Without `just`:

```bash
mix test
mix credo --strict
mix run priv/repo/seeds.exs
mix bravo.demo.tokens
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

## Tradeoffs

This repository is intentionally scoped as a production-sane MVP:
- two countries are implemented well instead of many superficially
- external providers are simulated behind behaviours and adapters
- advanced operations like realtime backoffice and Kubernetes manifests are left as evolution, not overbuilt into the MVP
- some outbound side effects are represented by the outbox infrastructure without fully fleshed external integrations
