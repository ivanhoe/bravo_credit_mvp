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

Use one value for `SECRET_KEY_BASE` and another for `GUARDIAN_SECRET_KEY`. `CLOAK_KEY` must be exactly 32 characters.

2. Install dependencies:

```bash
mix deps.get
```

3. Create and migrate the database:

```bash
mix ecto.setup
```

4. Start the app:

```bash
mix phx.server
```

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Documentation

- `docs/ARCHITECTURE.md` - initial architecture draft
- `docs/ARCHITECTURE_V2.md` - refined architecture
- `docs/IMPLEMENTATION_PLAN.md` - execution plan
- `docs/DELIVERY_CHECKLIST.md` - final delivery checklist for the public repo

## Status

Bootstrap in progress.
