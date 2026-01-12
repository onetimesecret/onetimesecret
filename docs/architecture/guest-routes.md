---
labels: api, guest-routes, v3
---

# Guest Routes Architecture

Guest routes provide anonymous API access for secret operations via `/api/v3/guest/*`, mirroring authenticated `/api/v3/secret/*` endpoints.

## Use Cases

- Public sharing links work without recipient authentication
- Anonymous secret creation from homepage
- Lightweight integrations without API key management

## Route Mapping

| Operation | Guest Route                            | Authenticated Route              |
| --------- | -------------------------------------- | -------------------------------- |
| Create    | `POST /api/v3/guest/secret/conceal`    | `POST /api/v3/secret/conceal`    |
| Generate  | `POST /api/v3/guest/secret/generate`   | `POST /api/v3/secret/generate`   |
| Metadata  | `GET /api/v3/guest/secret/:id`         | `GET /api/v3/secret/:id`         |
| Reveal    | `POST /api/v3/guest/secret/:id/reveal` | `POST /api/v3/secret/:id/reveal` |
| Receipt   | `GET /api/v3/guest/receipt/:id`        | `GET /api/v3/receipt/:id`        |
| Burn      | `POST /api/v3/guest/receipt/:id/burn`  | `POST /api/v3/receipt/:id/burn`  |

## Configuration

Toggle routes individually in `config.yaml`:

```yaml
site:
  interface:
    api:
      guest_routes:
        enabled: true # Global toggle
        conceal: true # Per-operation toggles
        generate: true
        reveal: true
        burn: true
        show: true
        receipt: true
```

Disabled routes return `403 Forbidden` with code `GUEST_ROUTES_DISABLED` (or `GUEST_{OPERATION}_DISABLED`). Authenticated users bypass these checks.

## Implementation

Entry point: `lib/onetime/logic/guest_route_gating.rb` - the `GuestRouteGating` module mixed into V3 logic classes.

Routes defined in `apps/api/v3/routes.txt` with `auth=noauth` strategy.

## Related

- [Secret Lifecycle](../product/secret-lifecycle.md) - State machine for secrets
- Issue #2190 - Original implementation
