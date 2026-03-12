# BravoCredit

BravoCredit is a multi-country credit application MVP built with **Phoenix, Oban, PostgreSQL, and LiveView**.  
This project implements the full backend flow requested by the technical challenge, including async provider data fetching, risk evaluation, native queueing, and webhook processing. 

A LiveView interface is provided as an Operations Console at `http://localhost:4000/operations`.

This README covers the essential architectural guidelines and the technical implementations supporting the system.

---

## 1. Setup and Execution Instructions

This repository utilizes `docker compose` to provide a zero-configuration, instant execution environment to respect the examiner's time. This command builds the Elixir application and provisions PostgreSQL automatically.

```sh
1. cp .env.example .env
2. docker compose up --build -d
3. open http://localhost:4000/operations
```

> The API and the interactive UI will be available immediately at `http://localhost:4000/operations`.
> The system health probe is verifiable at `http://localhost:4000/health`.

---

## 2. Assumptions

*   The challenge is implemented as a production-sane MVP, not a fully productized lending platform.
*   The system operates dynamically across the requested 6 countries (ES, PT, IT, MX, CO, BR), all powered by the same runtime architecture.
*   External banking providers are simulated behind asynchronous workers and external webhooks (idempotent).
*   The `/operations` console acts as an interactive dashboard for internal agents or credit analysts specifically for this MVP demonstration (hides raw payload logs in favor of business metrics).
*   `GET /api/applications/:id` returns a safe aggregate snapshot, explicitly masking raw PII document numbers for security best practices.

---

## 3. Data Model

PostgreSQL acts as the absolute source of truth. The application follows a Domain-Driven flow where state is derived transactionally. 

Main persisted entities:
*   **`applications`:** The main aggregate snapshot containing encrypted PII, dynamic financial data, and current operational states (Pending, Evaluating, Approved).
*   **`application_events`:** Append-only persistence model for deep business audit history over time.
*   **`event_outbox`:** Used for Transactional Outbox. **Populated via a native PostgreSQL trigger** reacting to the `application_events` table.
*   **`webhook_events`:** Persistent table storing external callback signatures to guarantee payload idempotency on retries.
*   **`oban_jobs`:** Native queue tables to distribute tasks in PostgreSQL reliably.

---

## 4. Technical Decisions

*   **Data-Driven Architecture (YAML):** 
    Instead of hardcoding hundreds of `if/else` lines per country in the Phoenix pipelines, the system leverages a **Strategy Pattern**. The entire feature set for a country (e.g., Financial thresholds, currency, document regexes like DNI or CPF) is defined statically in `config/countries/*.yaml`. The Elixir core acts purely as an agnostic execution engine.
*   **"Let It Crash" / Railway Pipelines:**
    Business operations avoid magic strings and throw highly specialized `%BravoCredit.Error{}` structs explicitly parsed and sent back to the LiveView UI (e.g., _"The DNI format requires 1 letter"_, _"Banking Provider unreachable"_).
*   **LiveView (Observer Pattern):**
    Elixir PubSub is used heavily. However, instead of passing vast state objects over websocket nodes, the UI receives microscopic pings (`"application_updated"`) and queries the persistent PostgreSQL database directly, reducing memory overhead massively for realtime updates.

---

## 5. Security Considerations

*   **PII Encryption at Rest:** Sensitive applicant information (Names, Identifiers) is structurally encrypted dynamically at rest via AES-GCM (Cipher) using `Cloak`. They can only be read back via in-memory keys (`CLOAK_KEY`).
*   **API Authentication:** Every internal path relies on strict Javascript Web Tokens (JWT) facilitated by `Guardian`.
*   **Geographic Authorization:** Elixir Plugs enforce country-scoped constraints (e.g., A Latin-American analyst trying to fetch `ES` applications via token gets instantly forbidden with a 403).

---

## 6. Scalability and High Volume Data Handling

If the system was subjected to tens of millions of credit requests, the persistence architecture is designed for vertical and horizontal read-heavy scaling:

*   **Recommended Indexes:**
    *   `(country_code, status)` applied directly to `applications` to prevent full table scans when rendering operations consoles.
    *   `(document_hash)` enables fast O(1) searches for duplicate or repeat loans without decrypting PII databases.
    *   `(application_id, inserted_at desc)` for fast timeline rendering on the `application_events` table.
*   **Partitioning Strategy (Table Structuring):**
    For massive workloads, the core `applications` and `application_events` tables align flawlessly with PostgreSQL declarative partitioning **by `country_code`** (List Partitioning). This strictly localizes disk caching by zone, allowing the Mexico partition to spin on NVMe separate from European loads.
*   **Bottlenecks (Asynchronous Eviction):**
    To avoid HTTP bottlenecking in an API environment, synchronous workers never wait on external APIs or heavy IO blocking risk engines. Transactional bounds insert `Oban` rows locally immediately.
*   **Archiving Strategy:**
    Approved or long-overdue applications (e.g., ~3 years) could be trivially evacuated safely using the `application_events` topic feed. The continuous outbox log acts effectively as a Change Data Capture (CDC) stream directly into S3 or a Cold Storage Lake, letting operations `TRUNCATE` cold partitions periodically without losing business compliance logic.

---

## 7. Concurrency, Queues, Cache & Webhooks Strategy

*   **Queuing & Concurrency:**
    The app uses **Oban**. Oban achieves robust parallel execution powered entirely by PostgreSQL SKIP LOCKED mechanics minimizing orchestration overhead. The processing happens in distinct phases (`FetchProviderData` -> `EvaluateRiskScore`), handled simultaneously by independent parallel background workers.
*   **Caching Strategy:**
    High-read & zero-write objects like the master configuration rules loaded from `countries/*.yaml` bypass the database completely using Erlang's native **ETS (Erlang Term Storage)** tables (`BravoCredit.Cache`).
    *   _Invalidation:_ The cache acts as an immutable lookup table for business rules loaded upon booting. Due to the high availability inherent to k8s deployments, cache invalidation simply occurs via a Rolling Graceful Pod restart.
*   **Webhooks (External Processes):**
    The application receives webhook updates (`POST /api/webhooks/provider`) via native idempotent keys. `webhook_events` is used defensively mapping external event IDs strictly; processing stops structurally throwing 409 Conflicts in the event a simulated banking provider double-pings a state update.

---

### Implemented Extras
- Kubernetes Configurations (k8s manifests included in `./k8s/`).
- Complete originations expanded into 6 countries.
- Native Realtime interactive flow directly integrated (LiveView).

_(For auxiliary documentation on cURL workflows and Database Seeding, see `./docs/API_AND_SEEDING.md`)_
