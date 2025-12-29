---
labels: api, guest-routes, v3
---
# Guest Routes API Reference

**Last Updated:** 2025-12-28
**Base Path:** `/api/v3/guest`
**Related Issue:** #2190

## Overview

Guest routes provide anonymous (unauthenticated) API access for secret operations. These endpoints mirror the authenticated `/api/v3/secret/*` routes but allow access without credentials.

Guest routes are useful for:
- Public sharing links that work without authentication
- Integration scenarios where API keys are not practical
- Anonymous secret creation and retrieval

## Authentication

Guest routes use the `auth=noauth` Otto strategy, meaning **no authentication is required**. The same endpoints work for both anonymous users and authenticated users.

| Method | Header | Required |
|--------|--------|----------|
| None | - | No authentication needed |

## Configuration

Guest routes can be enabled or disabled via configuration in `config.yaml`:

```yaml
site:
  interface:
    api:
      guest_routes:
        # Global toggle - disables all guest routes when false
        enabled: true
        # Fine-grained controls (checked only when enabled=true)
        conceal: true    # POST /api/v3/guest/secret/conceal
        generate: true   # POST /api/v3/guest/secret/generate
        reveal: true     # POST /api/v3/guest/secret/:id/reveal
        burn: true       # POST /api/v3/guest/receipt/:id/burn
        show: true       # GET  /api/v3/guest/secret/:id
        receipt: true    # GET  /api/v3/guest/receipt/:id
```

### Environment Variables

All toggles can be set via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `API_GUEST_ROUTES_ENABLED` | `true` | Global toggle |
| `API_GUEST_CONCEAL` | `true` | Enable guest conceal |
| `API_GUEST_GENERATE` | `true` | Enable guest generate |
| `API_GUEST_REVEAL` | `true` | Enable guest reveal |
| `API_GUEST_BURN` | `true` | Enable guest burn |
| `API_GUEST_SHOW` | `true` | Enable guest show |
| `API_GUEST_RECEIPT` | `true` | Enable guest receipt |

### Behavior When Disabled

When guest routes are disabled (globally or per-operation), requests from anonymous users receive:

```json
{
  "message": "Guest API access is disabled",
  "code": "GUEST_ROUTES_DISABLED"
}
```

Or for operation-specific disabling:

```json
{
  "message": "Guest conceal is disabled",
  "code": "GUEST_CONCEAL_DISABLED"
}
```

**HTTP Status:** `403 Forbidden`

**Note:** Authenticated users are never affected by guest route configuration. The checks only apply to requests from anonymous users using `auth=noauth`.

## Endpoints

| Method | Path | Description | Config Key |
|--------|------|-------------|------------|
| POST | `/guest/secret/conceal` | Create secret from user-provided value | `conceal` |
| POST | `/guest/secret/generate` | Create secret with generated value | `generate` |
| GET | `/guest/secret/:identifier` | Show secret metadata | `show` |
| POST | `/guest/secret/:identifier/reveal` | Reveal and consume secret | `reveal` |
| GET | `/guest/receipt/:identifier` | Show metadata/receipt | `receipt` |
| POST | `/guest/receipt/:identifier/burn` | Burn/destroy secret | `burn` |

## Endpoint Details

### POST /guest/secret/conceal

Create a new secret from a user-provided value.

**Request:**
```json
{
  "secret": {
    "secret": "my sensitive password",
    "ttl": 3600,
    "passphrase": "optional-passphrase"
  }
}
```

**Response (200 OK):**
```json
{
  "record": {
    "metadata": {
      "key": "abc123...",
      "identifier": "m:abc123..."
    },
    "secret": {
      "identifier": "s:def456..."
    }
  },
  "details": {
    "share_url": "https://example.com/secret/def456...",
    "receipt_url": "https://example.com/private/abc123..."
  }
}
```

### POST /guest/secret/generate

Create a new secret with a system-generated random value.

**Request:**
```json
{
  "secret": {
    "ttl": 3600,
    "passphrase": "optional-passphrase"
  }
}
```

**Response (200 OK):**
```json
{
  "record": {
    "metadata": {
      "key": "abc123...",
      "identifier": "m:abc123..."
    },
    "secret": {
      "identifier": "s:def456..."
    }
  },
  "details": {
    "generated_value": "xK9#mP2$nL7...",
    "share_url": "https://example.com/secret/def456...",
    "receipt_url": "https://example.com/private/abc123..."
  }
}
```

### GET /guest/secret/:identifier

Show metadata about a secret without revealing its value.

**Response (200 OK):**
```json
{
  "record": {
    "identifier": "s:def456...",
    "state": "new",
    "has_passphrase": false
  },
  "details": {
    "continue": false,
    "is_owner": false,
    "show_secret": false
  }
}
```

### POST /guest/secret/:identifier/reveal

Reveal and consume a secret. The secret is destroyed after this call.

**Request:**
```json
{
  "passphrase": "optional-if-required",
  "continue": "true"
}
```

**Response (200 OK):**
```json
{
  "record": {
    "identifier": "s:def456...",
    "secret_value": "my sensitive password"
  },
  "details": {
    "show_secret": true,
    "correct_passphrase": true
  }
}
```

### GET /guest/receipt/:identifier

Show metadata/receipt for a secret by its metadata identifier.

**Response (200 OK):**
```json
{
  "record": {
    "identifier": "m:abc123...",
    "state": "new",
    "secret_identifier": "s:def456...",
    "natural_expiration": "1 hour",
    "share_url": "https://example.com/secret/def456..."
  },
  "details": {
    "show_secret": true,
    "show_secret_link": true
  }
}
```

### POST /guest/receipt/:identifier/burn

Destroy a secret before it expires or is revealed.

**Request:**
```json
{
  "continue": "true"
}
```

**Response (200 OK):**
```json
{
  "record": {
    "identifier": "m:abc123...",
    "state": "burned"
  }
}
```

## Error Response Format

All errors follow the standard JSON format:

```json
{
  "message": "Error description",
  "code": "ERROR_CODE"
}
```

### Common Error Codes

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `GUEST_ROUTES_DISABLED` | 403 | Guest routes globally disabled |
| `GUEST_CONCEAL_DISABLED` | 403 | Guest conceal operation disabled |
| `GUEST_GENERATE_DISABLED` | 403 | Guest generate operation disabled |
| `GUEST_REVEAL_DISABLED` | 403 | Guest reveal operation disabled |
| `GUEST_BURN_DISABLED` | 403 | Guest burn operation disabled |
| `GUEST_SHOW_DISABLED` | 403 | Guest show operation disabled |
| `GUEST_RECEIPT_DISABLED` | 403 | Guest receipt operation disabled |

## Usage Examples

### Create a Secret (curl)

```bash
curl -X POST https://example.com/api/v3/guest/secret/conceal \
  -H "Content-Type: application/json" \
  -d '{"secret": {"secret": "my password", "ttl": 3600}}'
```

### Generate a Secret (curl)

```bash
curl -X POST https://example.com/api/v3/guest/secret/generate \
  -H "Content-Type: application/json" \
  -d '{"secret": {"ttl": 86400}}'
```

### Reveal a Secret (curl)

```bash
curl -X POST https://example.com/api/v3/guest/secret/abc123/reveal \
  -H "Content-Type: application/json" \
  -d '{"continue": "true"}'
```

### With Passphrase (curl)

```bash
curl -X POST https://example.com/api/v3/guest/secret/abc123/reveal \
  -H "Content-Type: application/json" \
  -d '{"passphrase": "secret-passphrase", "continue": "true"}'
```

## Comparison: Guest vs Authenticated Routes

| Feature | Guest Routes | Authenticated Routes |
|---------|--------------|---------------------|
| Base Path | `/api/v3/guest/*` | `/api/v3/secret/*` |
| Authentication | None required | Session or API key |
| Rate Limiting | Standard | Based on plan |
| Configurable | Per-operation toggles | Always enabled |
| Entitlement Check | Not applicable | Requires `api_access` |

## Implementation Notes

### Logic Class Inheritance

Guest routes use V3 logic classes which inherit from V2 but add guest route gating:

```
V3::Logic::Secrets::ConcealSecret
  -> inherits V2::Logic::Secrets::ConcealSecret
  -> includes Onetime::Logic::GuestRouteGating
```

### Check Order in raise_concerns

1. Guest route check (`require_guest_route_enabled!`)
2. Entitlement check (`require_entitlement!`)
3. Business logic validation

### Key Files

| File | Description |
|------|-------------|
| `lib/onetime/logic/guest_route_gating.rb` | GuestRouteGating module |
| `apps/api/v3/logic/secrets.rb` | V3 logic classes with gating |
| `apps/api/v3/routes.txt` | Route definitions |
| `lib/onetime/errors.rb` | GuestRoutesDisabled exception |
| `lib/onetime/application/otto_hooks.rb` | Error handler registration |
