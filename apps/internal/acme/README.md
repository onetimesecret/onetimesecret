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
GET /api/internal/acme/ask?domain=example.com
```

| Status | Meaning |
|--------|---------|
| 200 | Domain verified — issue certificate |
| 400 | Missing `domain` parameter |
| 401 | Request not from localhost |
| 403 | Domain not found or not verified |

## Security

- **Localhost-only**: `LocalhostOnly` middleware rejects non-loopback IPs (127.0.0.1, ::1, ::ffff:127.0.0.1)
- **Fail-closed**: Database errors return 403 (no certificate issued)
- **DNS ownership required**: Only domains with `ready?` status (DNS TXT verified) are allowed

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

## Testing

### RSpec (32 specs, all currently skipped)

The spec file at `spec/application_spec.rb` covers domain validation, error handling,
`LocalhostOnly` middleware, and routing. All specs are unconditionally skipped via
`before(:all) { skip }` because they require a full application boot environment.

```bash
# Via rake (auto-discovered, but all 32 specs will be pending)
bundle exec rake spec:apps:internal_acme

# Or via pnpm
pnpm run test:rspec:apps:internal:acme
```

The smoke test suite (`rake smoke:rspec`) intentionally skips this app since it's 100% pending.

To actually execute the specs, remove the `before(:all) { skip }` block (lines 12-14)
and run with a live database:

```bash
RACK_ENV=test VALKEY_URL=redis://localhost:6379/15 \
  bundle exec rspec apps/internal/acme/spec/application_spec.rb
```

The specs mock `Onetime::CustomDomain` but still need `spec_helper` to boot
the OT environment (`OT.ld`, `OT.info`, `OT.le` logging).

### Manual curl

```bash
# Verified domain → 200
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=your-domain.com"

# Missing param → 400
curl "http://127.0.0.1:3000/api/internal/acme/ask"

# Unknown domain → 403
curl "http://127.0.0.1:3000/api/internal/acme/ask?domain=nonexistent.example.com"
```

## Architecture

```
Caddy TLS request
  → on_demand_tls ask endpoint
    → LocalhostOnly middleware (401 if not loopback)
      → AskHandler
        → Application.domain_allowed?(domain)
          → CustomDomain.load_by_display_domain
            → custom_domain.ready? (DNS TXT verified?)
              → 200 OK / 403 Forbidden
```

The app implements `should_skip_loading?` — it only loads when `features.domains.acme.enabled` is `true` in config. It uses `Rack::CommonLogger` in development (not the main app's `RequestLogger`) to stay self-contained.
