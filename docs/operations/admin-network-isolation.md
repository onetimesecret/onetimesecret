# Admin network isolation (`site.admin.allowed_cidrs`)

Operator guide for restricting the Colonel admin surfaces to a trusted network
as **defense-in-depth**, on top of the application's own authentication and
authorization.

## What it does

The Colonel admin console ships as two surfaces:

- `/colonel` (and `/colonel/*`) — the admin shell served by the core web app.
- `/api/colonel` (and `/api/colonel/*`) — the admin JSON API.

Both are already protected by **two app-layer auth layers** that always enforce:

1. `role=colonel` at the Otto router (`apps/api/colonel/routes.txt`, scope
   `internal`), and
2. `verify_one_of_roles!(colonel: true)` (plus `cust.verified?`) in each logic
   class.

`site.admin.allowed_cidrs` adds an **optional network layer in front** of those.
When configured, a request whose trusted-proxy-resolved client IP falls
**outside** the allowlist receives a **404** — not a 403 — on both surfaces, so
the admin console is *indistinguishable from absent* to an unauthorized network
and does not advertise its existence. It is enforced by the
`AdminNetworkIsolation` Rack middleware
(`lib/onetime/middleware/admin_network_isolation.rb`), a sibling of the existing
`IPBan` and `HealthAccessControl` middleware.

Isolation is a **config posture, not a code fork**: the exact same app-layer
enforcement runs in both postures. Flipping the allowlist on or off never
changes the auth behavior beneath it.

## Default: no-op (self-hosted single-container)

When `site.admin.allowed_cidrs` is **unset or empty**, the middleware is a strict
**no-op** — both surfaces stay reachable and the two auth layers are the sole
gate. This is the intended default for self-hosted single-container installs,
which cannot require a VPN. **No new configuration is required** for an existing
install to keep working.

## Cloud enablement (private CIDRs)

On a cloud deployment where operators reach the admin console over a VPN or
private network (e.g. Tailscale, WireGuard, an office range), set the allowlist
to the **private** ranges the surfaces should be reachable from:

```yaml
# etc/config.yaml
site:
  admin:
    allowed_cidrs:
      - 100.64.0.0/10   # Tailscale / CGNAT VPN range
      - 10.0.0.0/8      # internal RFC1918
```

Or via environment variable (comma-separated):

```bash
ADMIN_ALLOWED_CIDRS=100.64.0.0/10,10.0.0.0/8
```

Now a request to `/colonel` or `/api/colonel` from any IP outside those ranges
gets a 404; a request from inside passes through to the normal auth layers.

### Behind a reverse proxy or load balancer — required

The allowlist is checked against the **trusted-proxy-resolved** client IP, the
same value the rest of the stack uses (ban checks, sessions, audit attribution).
It is resolved from `env['otto.client_ip']`, set once by the universal IP-privacy
middleware from `site.network.trusted_proxy`. A **raw `X-Forwarded-For` header
cannot bypass the allowlist** — that is the point.

Consequently, if the app runs behind a reverse proxy, ingress, or load balancer,
you **must** also configure `site.network.trusted_proxy` (see
`.env.reference`, `TRUSTED_PROXY_*`). Otherwise every request resolves to the
proxy's own hop IP, and either all requests are allowed (if that hop is inside
the allowlist) or all are denied. Example:

```yaml
site:
  network:
    trusted_proxy:
      enabled: true
      mode: filter          # or depth, per your topology
  admin:
    allowed_cidrs:
      - 100.64.0.0/10
```

Use **private ranges only**. Do not put a public CIDR in `allowed_cidrs`;
network isolation is meant to limit the surface to a private/VPN network, and
the app-layer auth layers remain the gate for anyone who is on that network.

## Self-hosted alternative: reverse proxy (Caddy)

Self-hosted operators who want network isolation without turning on the app-level
allowlist can instead **not expose the admin paths at the edge at all** and front
them with a reverse proxy. This keeps the single-container default (`allowed_cidrs`
empty, middleware no-op) while achieving the same network posture at the proxy.

Example Caddyfile that returns 404 for `/colonel*` and `/api/colonel*` unless the
client is in a private range:

```caddy
example.com {
    @admin path /colonel* /api/colonel*

    @admin_untrusted {
        path /colonel* /api/colonel*
        not remote_ip 100.64.0.0/10 10.0.0.0/8 192.168.0.0/16
    }
    # Return 404 (indistinguishable-from-absent), not 403.
    respond @admin_untrusted 404

    reverse_proxy localhost:3000
}
```

Notes:

- Use `respond ... 404` (not `403`) to match the app middleware's
  indistinguishable-from-absent behavior.
- `remote_ip` matches Caddy's view of the connecting client. If Caddy itself is
  behind another proxy, use `client_ip` with `trusted_proxies` configured, so the
  match is not made against an intermediary hop.
- nginx equivalent: an `allow`/`deny` block on `location ~ ^/(api/)?colonel` that
  `return 404;` for untrusted addresses, using `set_real_ip_from` /
  `real_ip_header` if fronted by another proxy.

Either posture — app-level `allowed_cidrs` or an edge reverse-proxy rule — leaves
the two app-layer auth layers fully in force underneath.

## Verifying

- From an IP **outside** the allowlist: `GET /colonel` and `GET /api/colonel`
  both return `404`.
- From an IP **inside** the allowlist: the request reaches the auth layers
  (e.g. `401/403` without a colonel session, `200` with one) — i.e. the
  middleware passes through.
- With `allowed_cidrs` empty: both surfaces are reachable regardless of origin
  (no-op).
- A spoofed `X-Forwarded-For: <allowed-ip>` from an untrusted origin does **not**
  bypass the allowlist (resolution ignores raw headers unless a matching trusted
  proxy is configured).
