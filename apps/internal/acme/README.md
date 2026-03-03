# Internal ACME Application

Domain validation endpoint for [Caddy's on-demand TLS](https://caddyserver.com/docs/automatic-https#on-demand-tls). Caddy calls this before issuing certificates to verify the domain is registered and DNS-verified in our system.

## Running

**Currently**: The ACME app has no dedicated runner. It is auto-discovered by the application registry (`apps/**/application.rb` glob) and mounted at `/api/internal/acme` inside the main Rack process:

```bash
# Starts all apps including ACME, default port 3000
puma -e development -p 3000 config.ru
```

The endpoint is then available at `http://127.0.0.1:3000/api/internal/acme/ask`.

**Production with Caddy**: The config defines a separate `listen_address` and `port` (12020) for Caddy to call, but no standalone process or config.ru exists yet to run the ACME app on that port independently. To use with Caddy today, either:

1. Point Caddy's `ask` URL at the main app port (`http://127.0.0.1:3000/api/internal/acme/ask`)
2. Or add a dedicated rackup file / Procfile entry to run ACME on port 12020

## Endpoint

```
GET /api/internal/acme/ask?domain=example.com[&check_verification=false]
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `domain` | yes | — | The domain to validate |
| `check_verification` | no | `true` | Set to `false` to skip DNS verification check (domain must still exist) |

| Status | Meaning |
|--------|---------|
| 200 | Domain allowed — issue certificate |
| 400 | Missing `domain` parameter |
| 401 | Request not from localhost |
| 403 | Domain not found or not verified |

## Security

- **Localhost-only**: `LocalhostOnly` middleware rejects non-loopback IPs (127.0.0.1, ::1, ::ffff:127.0.0.1)
- **Fail-closed**: Database errors return 403 (no certificate issued)
- **DNS ownership required**: Only domains with `ready?` status (DNS TXT verified) are allowed

### Blocking external access at the reverse proxy

The ACME endpoint is auto-mounted at `/api/internal/acme` inside the main Rack process. When the main process runs behind Caddy, this path is publicly routable unless explicitly blocked. As defense in depth — even with `LocalhostOnly` middleware active — block the path at the proxy layer so that misconfigured or removed middleware never exposes the endpoint:

```caddyfile
# Block external access to internal ACME endpoint.
# Caddy's on_demand_tls ask directive calls the backend directly,
# bypassing these route rules — so this block is safe to add.
@internal_acme path /api/internal/acme/*
respond @internal_acme 404
```

Caddy's `on_demand_tls { ask ... }` directive makes direct HTTP calls to the backend that bypass Caddy's own routing rules. Adding this block does not affect certificate validation.

## Configuration

```yaml
# etc/config.yaml
domains:
  validation_strategy: caddy_on_demand
  acme:
    enabled: true
    listen_address: 127.0.0.1
    port: 12020
```

Environment variables: `ACME_ENDPOINT_ENABLED`, `ACME_LISTEN_ADDRESS`, `ACME_PORT`.

## Caddy Integration

```caddyfile
on_demand_tls {
  ask http://127.0.0.1:12020/api/internal/acme/ask
}
```

By default, Caddy's `ask` URL enforces DNS verification — only domains with verified TXT records get certificates. To issue certificates for registered but not-yet-verified domains (e.g. during initial setup), append `check_verification=false`:

```caddyfile
on_demand_tls {
  ask http://127.0.0.1:12020/api/internal/acme/ask?check_verification=false
}
```

The domain must still exist in the CustomDomain database; this only skips the DNS ownership proof.

## Testing

### RSpec (50 specs)

The spec file at `spec/application_spec.rb` covers domain validation, error handling,
`LocalhostOnly` middleware, and routing. Specs are tagged `acme_integration: true` and
run as part of the standard test suite (via `spec:apps:all` and the dedicated `spec:acme` task).

```bash
# Run ACME specs directly
bundle exec rspec apps/internal/acme/spec/application_spec.rb

# Run via dedicated rake task
bundle exec rake spec:acme

# Also included in the full app specs run
bundle exec rake spec:apps:all
```

The specs mock `Onetime::CustomDomain` and stub `MiddlewareStack.configure`, so no
live database is needed. They do require `spec_helper` for the OT logging environment
(`OT.ld`, `OT.info`, `OT.le`).

### Manual curl

```bash
# Verified domain → 200
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=your-domain.com"

# Missing param → 400
curl "http://127.0.0.1:3000/api/internal/acme/ask"

# Unknown domain → 403
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=nonexistent.example.com"

# Unverified but registered domain → 403 (default)
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=pending.example.com"

# Skip verification (domain must still exist) → 200
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=pending.example.com&check_verification=false"
```

## Architecture

```
Caddy TLS request
  → on_demand_tls ask endpoint
    → LocalhostOnly middleware (401 if not loopback)
      → AskHandler (parses domain, check_verification)
        → Application.domain_allowed?(domain, check_verification:)
          → CustomDomain.load_by_display_domain
            → nil? → 403 Forbidden
            → check_verification false? → 200 OK
            → custom_domain.ready? (DNS TXT verified?)
              → 200 OK / 403 Forbidden
```

The app implements `should_skip_loading?` — it only loads when `features.domains.acme.enabled` is `true` in config. It uses `Rack::CommonLogger` in development (not the main app's `RequestLogger`) to stay self-contained.
