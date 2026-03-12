# BravoCredit - Agent Context

This file is the operational context for coding agents working in this repository.
It summarizes the implementation decisions already taken and the constraints that should be preserved.

## 1. Project Goal

BravoCredit is a production-sane MVP for multi-country credit applications built for a technical challenge.

Implemented business flow:
- create application
- fetch provider data asynchronously
- evaluate risk asynchronously
- expose authenticated application APIs
- process incoming provider webhooks with idempotency
- persist domain events
- dispatch PostgreSQL-triggered outbox work
- monitor the flow from LiveView operations screens

Countries currently implemented:
- `MX`
- `CO`

## 2. Current Product Scope

Core APIs:
- `POST /api/applications`
- `GET /api/applications`
- `GET /api/applications/:id`
- `PATCH /api/applications/:id/state`
- `POST /api/webhooks/provider`
- `GET /health`

Operations UI:
- `/operations`
- `/applications/new`
- `/applications/:id`

The root path `/` redirects to `/operations`.

## 3. Official Evaluation Flow

The repo is optimized for a reviewer to understand and run it quickly.

Official happy path:

```bash
docker compose up --build -d
open http://localhost:4000/operations
```

Health check:

```bash
curl http://localhost:4000/health
```

Important:
- `docker compose up --build -d` must start both `postgres` and `app`
- the flow should not depend on local Tailwind installation
- compiled frontend assets are intentionally committed under `priv/static`

## 4. Local Development Flow

If working outside Docker:

```bash
cp .env.example .env
set -a
source .env
set +a
docker compose up -d postgres
just setup
just server
```

`just` is available and configured with `dotenv-load := true`.

## 5. Environment Rules

Runtime-required env vars for local Mix commands:
- `SECRET_KEY_BASE`
- `GUARDIAN_SECRET_KEY`
- `CLOAK_KEY`
- `DATABASE_URL`
- `TEST_DATABASE_URL`

Rules:
- `SECRET_KEY_BASE` must be long enough for Phoenix cookies and LiveView sessions
- `CLOAK_KEY` must be exactly 32 bytes
- production-style secrets must come from env vars, not from code fallbacks

Docker Compose now provides local-safe defaults for the app container so reviewers can run the operations console without a handcrafted `.env`.

## 6. Architecture Decisions

### Domain and persistence

- PostgreSQL is the source of truth
- `applications` is the main aggregate
- `application_events` is append-only business audit history
- `event_outbox` is used for async side effects
- `webhook_events` persists idempotent external callbacks
- Oban is the job system

### Multi-country design

- country policies live in `config/countries/*.yaml`
- YAML stores business configuration, not executable logic
- Elixir code resolves symbolic ids through registries

Current country pieces:
- `MX`: CURP validation + MX provider + MX rules
- `CO`: CC validation + CO provider + CO rules

### Async model

Main async path:
- command persists aggregate + events + Oban jobs transactionally

PostgreSQL-native async requirement:
- `application_events` trigger inserts rows into `event_outbox`
- `DispatchOutbox` drains and handles those rows

### Monitoring / operations UI

LiveView is an observer, not the workflow owner.

Source of truth:
- PostgreSQL persisted state

Realtime mechanism:
- small PubSub broadcasts
- LiveViews re-query the database after notifications

Monitoring context:
- `BravoCredit.Monitoring`
- `BravoCredit.Monitoring.Broadcaster`

## 7. Error Handling Pattern

This repository uses Railway-style results for commands, pipelines, and workers.

Standard contract:

```elixir
{:ok, value}
{:error, %BravoCredit.Error{}}
```

Rules:
- expected business/integration errors are data
- unexpected failures may still raise
- controllers use `FallbackController`
- workers decide retry/discard using `retryable?`
- do not reintroduce exception-driven business flow

Relevant docs:
- `docs/CODING_GUIDELINES.md`
- `docs/RAILWAY_AND_ERRORS.md`

## 8. Code Conventions

- use structs for stable domain shapes
- use small modules with clear responsibilities
- keep return contracts consistent
- use `with` for linear happy paths
- use `case` when branching is clearer
- do not use `GenServer` only as a code-organizing trick
- prefer `%BravoCredit.Error{}` over loose atoms/strings/maps

Project-specific rules:
- pipeline steps operate on `Pipeline.Context`
- commands change state and return result tuples
- queries should avoid side effects
- workers should delegate to domain services/pipelines

## 9. Delivery Constraints To Preserve

Do not regress these:
- `docker compose up --build -d` should be enough to run the operations console
- `/operations` should render without needing local asset installation
- `mix setup` should not fail because frontend binaries could not be downloaded
- `priv/static` is intentionally committed for this challenge workflow

Do not reintroduce:
- `assets.setup` or `assets.build` into the critical `mix setup` path
- Docker build steps that depend on downloading Tailwind during evaluation
- app service behind a Compose profile for the main startup path
- hardcoded business rules outside YAML/registries unless strictly necessary

## 10. Quality Gates

Before committing meaningful code changes, validate:

```bash
mix compile
mix credo --strict
mix test
```

Current suite covers:
- schemas and changesets
- country config loading and validation
- document validators
- rules engine
- create application pipeline
- provider fetch worker
- risk evaluation worker
- authenticated application queries and transitions
- PostgreSQL-triggered outbox dispatch
- incoming provider webhook ingestion and processing
- monitoring LiveViews

## 11. Key Documentation

- `README.md`
- `docs/ARCHITECTURE_V2.md`
- `docs/IMPLEMENTATION_PLAN.md`
- `docs/CODING_GUIDELINES.md`
- `docs/RAILWAY_AND_ERRORS.md`
- `docs/DELIVERY_CHECKLIST.md`

## 12. Practical Note

If you change the Docker flow, asset pipeline, or environment bootstrapping, re-test the exact evaluator path:

```bash
docker compose up --build -d
curl http://localhost:4000/health
open http://localhost:4000/operations
```
