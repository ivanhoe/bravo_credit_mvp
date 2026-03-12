# BravoCredit

BravoCredit is a multi-country credit application MVP built with Phoenix, LiveView and PostgreSQL.

## Quick Start

1. Create and load your environment file:

```bash
cp .env.example .env
source .env
```

Generate secure values before the first run:

```bash
mix phx.gen.secret
mix phx.gen.secret
```

Use one value for `SECRET_KEY_BASE` and another for `GUARDIAN_SECRET_KEY`. `SECRET_KEY_BASE` must be at least 64 characters and `CLOAK_KEY` must be exactly 32 characters.
The default Docker Compose setup uses port `5433` to avoid conflicts with Postgres.app on macOS.

2. Start PostgreSQL with Docker Compose:

```bash
docker compose up -d postgres
```

3. Install dependencies:

```bash
mix deps.get
```

4. Create and migrate the database:

```bash
mix ecto.setup
```

5. Start the app:

```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Local Database

The project uses `docker-compose.yml` to run PostgreSQL locally.

Common commands:

```bash
docker compose up -d postgres
docker compose ps
docker compose logs -f postgres
docker compose down
```

`DATABASE_URL` and `TEST_DATABASE_URL` are expected to point to this Postgres instance.

If you have `just` installed, the same shortcuts are available through the `Justfile`.

## Documentation

- `docs/ARCHITECTURE.md` - initial architecture draft
- `docs/ARCHITECTURE_V2.md` - refined architecture
- `docs/IMPLEMENTATION_PLAN.md` - execution plan
- `docs/DELIVERY_CHECKLIST.md` - final delivery checklist for the public repo

## Status

Bootstrap in progress.
