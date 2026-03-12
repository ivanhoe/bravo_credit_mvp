# API & Seeding Reference

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
