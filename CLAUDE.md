# BravoCredit - Claude Context

This file gives Claude-style assistants the current project context so they can work without rediscovering the architecture every time.

## Project Summary

BravoCredit is a multi-country credit application MVP built with:
- Elixir
- Phoenix
- Phoenix LiveView
- PostgreSQL
- Oban
- Guardian
- Cloak

The system already implements:
- application creation
- async provider enrichment
- async risk evaluation
- authenticated read APIs
- manual state transitions
- provider webhook ingestion
- append-only domain events
- PostgreSQL-triggered outbox dispatch
- LiveView operations monitoring screens

Implemented countries:
- `MX`
- `CO`

## Canonical Startup Path

The evaluator-friendly startup flow is:

```bash
docker compose up --build -d
open http://localhost:4000/operations
```

Health endpoint:

```bash
curl http://localhost:4000/health
```

This flow is intentionally supported without requiring the reviewer to install frontend tooling locally.

## Important Operational Decisions

### 1. Frontend assets

- `priv/static` is intentionally committed
- Docker build no longer depends on running `mix assets.deploy`
- `mix setup` should not depend on downloading Tailwind or esbuild binaries

Do not undo this casually. It was chosen to make the challenge easy to run in under five minutes.

### 2. Docker

- `docker compose up --build -d` must start both the database and the app
- the app service should not be hidden behind a compose profile for the main path
- the final image must include `config/countries`

### 3. Runtime configuration

Secrets come from env vars for real Mix/runtime flows:
- `SECRET_KEY_BASE`
- `GUARDIAN_SECRET_KEY`
- `CLOAK_KEY`
- `DATABASE_URL`
- `TEST_DATABASE_URL`

Compose provides local-safe defaults for the containerized startup path.

## Architecture Model

### Aggregate and storage

- `applications` is the aggregate root
- `application_events` stores business history
- `event_outbox` stores async side-effect work
- `webhook_events` stores idempotent incoming callbacks
- Oban handles background jobs

### Country model

Country behavior is configured via YAML:
- `config/countries/mx.yaml`
- `config/countries/co.yaml`

YAML contains:
- document type
- validator id
- provider adapter id
- business rules and thresholds

YAML must remain declarative. No executable code references should leak into it beyond symbolic ids resolved by registries.

### Async model

Primary async path:
- application writes and Oban jobs are persisted transactionally

Challenge-specific DB-triggered async path:
- `application_events` trigger creates `event_outbox` rows
- outbox worker dispatches those side effects

### Monitoring model

LiveView is not the workflow engine.

It observes:
- persisted application state
- event history
- webhook rows
- outbox rows
- Oban jobs

Realtime updates come from PubSub notifications that trigger re-queries, not from holding workflow state in the socket.

## Error Model

This repo uses Railway-oriented flow for commands, pipelines, and workers.

Standard contract:

```elixir
{:ok, value}
{:error, %BravoCredit.Error{}}
```

Rules:
- expected errors are modeled as data
- unexpected faults may raise
- HTTP translation happens through `FallbackController`
- workers inspect `retryable?`

Do not replace this with exception-driven control flow.

## Coding Expectations

Follow these principles:
- prefer clarity over cleverness
- use structs for stable contracts
- keep function return shapes consistent
- use `with` for linear flows
- use `case` where branches deserve explicit treatment
- keep business logic out of LiveViews
- do not introduce OTP processes unless runtime behavior truly requires them

Primary reference docs:
- `docs/CODING_GUIDELINES.md`
- `docs/RAILWAY_AND_ERRORS.md`

## Current UI Surface

Routes:
- `/` -> redirects to `/operations`
- `/operations` -> monitoring dashboard
- `/applications/new` -> create application form
- `/applications/:id` -> application detail view

The detail view should continue to show:
- current stage
- aggregate state
- timeline
- webhooks
- outbox rows
- jobs
- manual transition controls
- webhook simulation controls

## Local Development Notes

If running locally without Docker app:

```bash
cp .env.example .env
set -a
source .env
set +a
docker compose up -d postgres
just setup
just server
```

`just` loads `.env` automatically.

## Quality Gates

Run before shipping meaningful changes:

```bash
mix compile
mix credo --strict
mix test
```

The test suite already covers the core flow and the LiveView monitoring surface.

## Do Not Break

These are high-priority invariants:
- operations console starts from Docker in a reviewer-friendly way
- `/health` returns `200`
- `/operations` renders successfully
- country YAML files are present in container runtime
- `mix setup` is not blocked by frontend binary downloads
- async workflow remains transactional and observable

## Reference Docs

- `README.md`
- `docs/ARCHITECTURE_V2.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/DELIVERY_CHECKLIST.md`
