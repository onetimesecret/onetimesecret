---
labels: api, guest-routes, v3
---
# Guest Routes Architecture

## What Are Guest Routes?

Guest routes provide anonymous (unauthenticated) API access for secret operations. They mirror the authenticated `/api/v3/secret/*` endpoints but allow access without credentials via the `/api/v3/guest/*` path.

## Why Guest Routes Exist

Guest routes serve three primary use cases:

1. **Public sharing links** - Secret URLs work without requiring recipients to authenticate
2. **Lightweight integrations** - API consumers can create/retrieve secrets without managing API keys
3. **Anonymous secret creation** - Users can create secrets from the homepage without an account

The key insight: secret *creation* and *retrieval* are fundamentally different from account *management*. A recipient only needs the secret link, not a relationship with the platform.

## Route Mapping

| Operation | Guest Route | Authenticated Route |
|-----------|-------------|---------------------|
| Create secret | `POST /api/v3/guest/secret/conceal` | `POST /api/v3/secret/conceal` |
| Generate secret | `POST /api/v3/guest/secret/generate` | `POST /api/v3/secret/generate` |
| Show metadata | `GET /api/v3/guest/secret/:id` | `GET /api/v3/secret/:id` |
| Reveal secret | `POST /api/v3/guest/secret/:id/reveal` | `POST /api/v3/secret/:id/reveal` |
| Show receipt | `GET /api/v3/guest/receipt/:id` | `GET /api/v3/receipt/:id` |
| Burn secret | `POST /api/v3/guest/receipt/:id/burn` | `POST /api/v3/receipt/:id/burn` |

## Configuration

Guest routes are individually toggleable via `config.yaml`:

```yaml
site:
  interface:
    api:
      guest_routes:
        enabled: true      # Global toggle
        conceal: true      # Per-operation toggles
        generate: true
        reveal: true
        burn: true
        show: true
        receipt: true
```

When disabled, anonymous requests receive `403 Forbidden` with code `GUEST_ROUTES_DISABLED` (or `GUEST_{OPERATION}_DISABLED` for per-operation toggles). Authenticated users bypass these checks entirely.

## Implementation

### Key Files

| File | Purpose |
|------|---------|
| `lib/onetime/logic/guest_route_gating.rb` | `GuestRouteGating` module with `require_guest_route_enabled!` |
| `apps/api/v3/logic/secrets.rb` | V3 logic classes that include gating |
| `apps/api/v3/routes.txt` | Otto route definitions |
| `lib/onetime/errors.rb` | `GuestRoutesDisabled` exception class |
| `lib/onetime/application/otto_hooks.rb` | Error handler registration |

### Class Hierarchy

V3 logic classes inherit from V2 and mix in guest route gating:

```
V3::Logic::Secrets::ConcealSecret
  ├─ inherits V2::Logic::Secrets::ConcealSecret
  └─ includes Onetime::Logic::GuestRouteGating
```

### Check Order

In `raise_concerns`, checks execute in this order:

1. **Guest route check** - `require_guest_route_enabled!` (skipped for authenticated users)
2. **Entitlement check** - `require_entitlement!`
3. **Business logic validation** - TTL limits, passphrase requirements, etc.

### Otto Strategy

Guest routes use `auth=noauth` in their Otto route definitions, meaning no authentication middleware runs. The same endpoints work for both anonymous and authenticated users—the gating module checks authentication state internally.

## Related

- [Secret Lifecycle](../product/secret-lifecycle.md) - State machine for secrets
- Issue #2190 - Original implementation
