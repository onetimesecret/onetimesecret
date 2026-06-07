# Catalog API Design

The API shape serves the consumer, not the storage model.

## Two endpoints, two shapes

| Endpoint | Question it answers | Shape |
|----------|---------------------|-------|
| `GET /billing/api/plans` | What can you buy? | Flat per-interval records |
| `GET /billing/api/org/:extid/overview` | What does this org have? | Single embedded plan |

Both serialize from the same internal model (`Billing::Plan`, family-keyed with nested `prices`), but to different shapes for different consumers.

## Catalog: flat per-interval records

The catalog endpoint expands family records into one record per interval:

```
identity_plus_v1 (family) → identity_plus_v1 (month) + identity_plus_v1 (year)
```

The frontend toggle filters by `plan.interval === billingInterval.value`. This works because each interval is its own record with `interval`, `amount`, and `stripe_price_id` at the top level.

This expansion is the serializer doing its job, not a compatibility shim. Stripe's own `GET /v1/prices` returns flat records even though a Product has many Prices.

## Overview: embedded plan snapshot

The overview endpoint returns the org's current subscribed plan with the specific interval they chose. This is denormalized (copied fields), not a catalog reference.

This is intentional:
- **Time independence**: If the catalog changes (rename, reprice), existing subscribers see their original terms
- **No frontend join**: The overview is self-contained; the frontend doesn't need to look up the catalog to display billing status

## Precedent

Stripe follows this pattern:
- `GET /v1/prices` returns flat catalog records
- `GET /v1/subscriptions/:id` embeds denormalized price/product data

The anti-pattern would be returning a catalog ID from the overview and forcing the frontend to join against the catalog to render the billing page.
