# Admin surface isolation (`site.admin.allowed_hosts` + `allowed_cidrs`)

Operator guide for restricting the Colonel admin surfaces to a trusted
**hostname** and a trusted **network**, as **defense-in-depth** on top of the
application's own authentication and authorization.

The two factors are independent and neither replaces the other:

| Factor | Config / env | Default |
|---|---|---|
| Host | `site.admin.allowed_hosts` / `ADMIN_ALLOWED_HOSTS` | **active** — canonical anchor hosts (+ `www.`) |
| Network | `site.admin.allowed_cidrs` / `ADMIN_ALLOWED_CIDRS` | inactive (opt-in) |

A request must pass every gate that is **active**. Failing either produces the
same 404. When both are inactive the middleware is a strict no-op.

## Upgrading

The host gate is new in #4062 and is **active without configuration**. Before
upgrading, confirm the hostname you use to reach `/colonel`:

- `features.domains.default` (`DEFAULT_DOMAIN`) or `site.host` (`HOST`), or a
  `www.` sibling of either → no change.
- Anything else — a tenant custom domain, a `LINK_DOMAINS` entry, an internal
  hostname → `/colonel` and `/api/colonel` return **404** on that hostname after
  the upgrade. Set `ADMIN_ALLOWED_HOSTS` to the hostname admin should be served
  on.
- No routable hostname at all (stock `HOST=localhost:3000`, or an install
  reached by bare IP) → no change; the gate self-disables. See [When the host
  gate goes inert](#when-the-host-gate-goes-inert).

If you do set `ADMIN_ALLOWED_HOSTS`, set it to something the gate can match: an
explicit list with no usable entry in it (an IP address, a `*.` pattern, a
non-ASCII name) **fails the boot** rather than quietly serving admin everywhere.
See [When boot refuses to start](#when-boot-refuses-to-start).

**Rollback is one variable:** `ADMIN_ALLOWED_HOSTS=*` restores the pre-#4062
behavior — the host gate off, logged at WARN on boot. The CIDR gate is
unaffected by it. It is also the only value that turns the gate off on purpose;
nothing else does.

The middleware also moved below `Rack::DetectHost` (which is below
`StartupReadiness`), so a request to `/colonel` *while the app is still booting*
now returns 503 rather than 404.

## What it does

The Colonel admin console ships as two surfaces:

- `/colonel` (and `/colonel/*`) — the admin shell served by the core web app.
- `/api/colonel` (and `/api/colonel/*`) — the admin JSON API.

Both are already protected by **two app-layer auth layers** that always enforce:

1. `role=colonel` at the Otto router (`apps/api/colonel/routes.txt`, scope
   `internal`), and
2. `verify_one_of_roles!(colonel: true)` (plus `cust.verified?`) in each logic
   class.

`site.admin.allowed_hosts` and `site.admin.allowed_cidrs` add a **host layer**
and a **network layer** in front of those. A request that fails either receives
a **404** — not a 403 — on both surfaces, so the admin console is
*indistinguishable from absent* to an unauthorized host or network and does not
advertise its existence. Both are enforced by the `AdminNetworkIsolation` Rack
middleware (`lib/onetime/middleware/admin_network_isolation.rb`), a sibling of
the existing `IPBan` and `HealthAccessControl` middleware.

Isolation is a **config posture, not a code fork**: the exact same app-layer
enforcement runs in every posture. Flipping either allowlist on or off never
changes the auth behavior beneath it.

## Host allowlist (`site.admin.allowed_hosts`)

Without a host gate the admin surfaces answer on **every hostname the app
serves**, including tenant custom domains and operator link-pool domains
(`features.domains.link_domains`). Session cookies are host-only and
custom-domain sign-in is off by default, so this is not by itself a takeover
path — but on a custom domain with sign-in enabled, a colonel who signs in there
gets the full admin console on a hostname the tenant controls in DNS. The gate
removes the surface rather than relying on those defaults holding.

**Unset or empty (the default) is active, not off.** The allowlist falls back to
the deployment's canonical *anchor* hosts — `features.domains.default` and
`site.host` — plus their `www.` siblings (an anchor configured as
`www.example.com` also admits `example.com`). A stock canonical deployment sees
no behavior change; custom domains and link-pool domains stop serving admin.

```bash
# Serve admin on its own hostname (recommended)
ADMIN_ALLOWED_HOSTS=admin.example.com
```

Details that matter:

- The host is taken from the **validated detected host** (`Rack::DetectHost`),
  which only honors a forwarded host header when the peer is trusted — see
  [Behind a reverse proxy or load balancer](#behind-a-reverse-proxy-or-load-balancer--required-for-both-gates).
  It is never read from a raw `Host` header or from the `O-Domain-Context`
  development header.
- **Explicit entries match literally** — list the `www.` form too if you need
  it. The `www.` tolerance applies only to the canonical fallback.
- Matching is case-insensitive, port-stripped and trailing-dot-stripped. ASCII
  A-labels only: give an internationalized domain in its `xn--` punycode form. A
  non-ASCII entry can never match, so it is dropped and named in a boot WARN —
  and if it was the *only* entry, the boot fails.
- **Patterns are not supported.** `*.example.com` matches nothing: it is dropped
  and named in a boot WARN, and a list of nothing but patterns fails the boot.
  List each hostname explicitly.
- **A nil or unresolvable detected host is a 404** while the gate is active.
- `ADMIN_ALLOWED_HOSTS=*` (as the sole entry) disables the host gate, logged at
  WARN on boot. The CIDR gate is unaffected. A list that mixes `*` with named
  hosts is ambiguous: the `*` is dropped (with a WARN) and the named hosts are
  enforced.
- Both allowlists are resolved **once, at boot**. A config or env change needs a
  restart.

### When the host gate goes inert

`Rack::DetectHost` never emits `localhost`, `localhost.localdomain`, an IP
literal, or anything else it does not consider a routable hostname — so on stock
local-dev (`HOST=localhost:3000`) and on bare-IP self-hosted installs there is
no detected host at all.

This applies to the **fallback only**. When `ADMIN_ALLOWED_HOSTS` is unset and
neither anchor (`DEFAULT_DOMAIN`, `HOST`) is a hostname the app could ever
detect, the host gate **self-disables** and logs at boot:

```
Admin host allowlist INACTIVE: no routable hostname configured
  source: "canonical anchors"
```

That keeps single-container installs working out of the box instead of locking
their operators out of `/colonel`. Set a routable hostname (via
`ADMIN_ALLOWED_HOSTS`, `HOST`, or `DEFAULT_DOMAIN`) to turn the gate on.

Nothing an operator writes into `ADMIN_ALLOWED_HOSTS` reaches this rule. A list
that was set but cannot be enforced does not go inert — it fails the boot.

### When boot refuses to start

If `ADMIN_ALLOWED_HOSTS` is **set and non-empty** but no entry survives — every
entry is an IP address, a `*.` pattern, a non-ASCII name, or not a hostname at
all — the app raises a config error at boot naming each entry and why:

```
ADMIN_ALLOWED_HOSTS (site.admin.allowed_hosts) names no hostname the admin host
gate could ever match, so /colonel and /api/colonel would be served on every
hostname: "127.0.0.1": not a routable hostname — localhost forms and IP literals
are never detected as a host. Set it to a routable hostname the deployment
answers on (ADMIN_ALLOWED_HOSTS=admin.example.com), unset it entirely to allow
the canonical host only, or set it to * to disable the host gate deliberately.
```

Refusing to boot is deliberate. Every one of these values is an operator writing
an allowlist in order to **restrict** the admin surfaces; disabling the gate on
a typo would do the opposite of what was asked and serve `/colonel` on every
hostname the app answers on. The three ways out are the three in the message:
name a routable hostname, unset it (canonical hosts only), or ask for the gate
to be off with `ADMIN_ALLOWED_HOSTS=*`.

Common triggers:

| Value | Result |
|---|---|
| `ADMIN_ALLOWED_HOSTS=127.0.0.1` / `localhost` | boot error — never detected as a host |
| `ADMIN_ALLOWED_HOSTS=*.example.com` | boot error — patterns are not supported |
| `ADMIN_ALLOWED_HOSTS=ünïcode.example` | boot error — supply the `xn--` form |
| `ADMIN_ALLOWED_HOSTS=*.example.com,admin.example.com` | boots; the pattern is dropped with a WARN, `admin.example.com` is enforced |
| `ADMIN_ALLOWED_HOSTS=*` | boots; host gate off, WARN |
| unset / empty | boots; canonical anchors, or inert (above) |

Partial failures are not fatal: as long as **one** entry is enforceable, the
rest are dropped with a WARN (`Ignoring unusable entries in
site.admin.allowed_hosts`) and the survivors are enforced.

## Network allowlist (`site.admin.allowed_cidrs`)

### Default: no-op (self-hosted single-container)

When `site.admin.allowed_cidrs` is **unset or empty**, the network gate is a
strict **no-op** — the surfaces stay reachable from any IP and the auth layers
(plus the host gate above) are the remaining gates. This is the intended default
for self-hosted single-container installs, which cannot require a VPN. No new
configuration is required to keep this factor as it was.

### Cloud enablement (private CIDRs)

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

Use **private ranges only**. Do not put a public CIDR in `allowed_cidrs`;
network isolation is meant to limit the surface to a private/VPN network, and
the app-layer auth layers remain the gate for anyone who is on that network.

## Behind a reverse proxy or load balancer — required for both gates

Each gate reads an input a proxy can rewrite, and each resolves that input the
same way the rest of the stack does:

- The **network** gate matches the **trusted-proxy-resolved** client IP — the
  same value used for ban checks, sessions and audit attribution, read from
  `env['otto.client_ip']`, which the universal IP-privacy middleware sets from
  `site.network.trusted_proxy`. A **raw `X-Forwarded-For` header cannot bypass
  the allowlist** — that is the point.
- The **host** gate matches the host `Rack::DetectHost` validated. Forwarded
  host headers (`X-Forwarded-Host`, `Apx-Incoming-Host`, `X-Original-Host`,
  `Forwarded`) are honored only for requests that arrived through trusted
  infrastructure.

Consequently, if the app runs behind a reverse proxy, ingress, or load balancer,
you **must** also configure `site.network.trusted_proxy` (see `.env.reference`,
`TRUSTED_PROXY_*`). Otherwise every request resolves to the proxy's own hop IP,
and either all requests are allowed (if that hop is inside the allowlist) or all
are denied. Example:

```yaml
site:
  network:
    trusted_proxy:
      enabled: true
      mode: filter          # depth mode is broken, see #4024
  admin:
    allowed_cidrs:
      - 100.64.0.0/10
```

**With `trusted_proxy` disabled (the default), host detection falls back to a
legacy heuristic**: any peer connecting from a private or loopback address is
trusted to set a forwarded host header. That keeps single-container installs
behind a local proxy working, but it also means anything able to open a
connection from a private address — another container on the same network, an
SSRF egress — can choose the host the gate sees. The client IP behind the CIDR
gate has the same dependency: with no trusted proxy declared it is resolved from
`REMOTE_ADDR`. Configure `trusted_proxy` on any deployment where a private-
address peer is reachable.

Because that state qualifies both gates, it is reported on the same boot line
they are — `trusted_proxy: disabled` sitting next to `host_gate: active` is the
combination to look for. See [Verifying](#verifying).

## Edge alternative: return 404 at the proxy (Caddy / nginx)

An edge rule depends on no input the app has to trust, so it holds even if the
app is misconfigured. Serve admin on its own hostname and 404 the admin paths on
every other vhost:

```caddy
# Admin answers only on its own hostname.
admin.example.com {
    reverse_proxy localhost:3000
}

# Every other vhost 404s the admin paths, whatever the app is configured to do.
example.com {
    @admin path /colonel* /api/colonel*
    respond @admin 404

    reverse_proxy localhost:3000
}
```

Self-hosted operators who want network isolation without turning on the
app-level CIDR allowlist can front the admin paths the same way, keeping the
single-container default (`allowed_cidrs` empty, network gate inactive) while
achieving the same posture at the proxy:

```caddy
example.com {
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

Every posture — app-level allowlists, an edge rule, or both — leaves the two
app-layer auth layers fully in force underneath.

## Recommended posture

- **Serve admin on its own hostname** (`admin.example.com`) and have the edge
  return 404 for `/colonel` and `/api/colonel` on every *other* vhost. Set
  `ADMIN_ALLOWED_HOSTS` to that hostname so the app enforces the same thing.
- Do not terminate the admin hostname on a wildcard vhost that also serves
  tenant custom domains.
- **Keep `ADMIN_ALLOWED_CIDRS`** (VPN/Tailscale/office ranges). Host and network
  are independent factors; neither replaces the other.
- `site.network.trusted_proxy` must be configured correctly or **both** gates
  read attacker-influenceable inputs. Depth mode is currently broken (#4024) —
  prefer CIDR matchers until that lands.

## Verifying

- On a host **not** on the allowlist (e.g. a tenant custom domain): `GET
  /colonel` and `GET /api/colonel` both return `404`, for an authenticated
  colonel and an anonymous request alike.
- On an allowlisted host: the request reaches the auth layers, exactly as
  before.
- From an IP **outside** the allowlist: `GET /colonel` and `GET /api/colonel`
  both return `404`.
- From an IP **inside** the allowlist: the request reaches the auth layers
  (e.g. `401/403` without a colonel session, `200` with one) — i.e. the
  middleware passes through.
- With `allowed_cidrs` empty: the network factor imposes nothing; reachability
  is decided by the host gate and the auth layers.
- With `ADMIN_ALLOWED_HOSTS` set to something unenforceable (`127.0.0.1`,
  `*.example.com`): the process **does not start** — it exits with a config
  error naming the entries. Nothing is served, including the admin surfaces.
- A spoofed `X-Forwarded-For: <allowed-ip>` from an untrusted origin does **not**
  bypass the CIDR allowlist, and a spoofed `X-Forwarded-Host` /
  `Apx-Incoming-Host` does **not** bypass the host allowlist — neither header is
  honored unless the peer is trusted (see the heuristic caveat above for
  private-address peers with `trusted_proxy` off).

### The boot log

One INFO line per process states the effective posture of both factors:

```
Admin surface isolation posture --
  {host_gate: "active", allowed_hosts: ["admin.example.com"],
   network_gate: "active", allowed_cidrs: ["100.64.0.0/10"],
   trusted_proxy: "enabled (mode=filter)",
   surfaces: ["/colonel", "/api/colonel"]}
```

Read it as three facts, not one:

- `host_gate` / `network_gate` — `active` or `inactive`. An `inactive` gate is
  distinguishable from a misconfigured one here without diffing config against
  source.
- `allowed_hosts` / `allowed_cidrs` — what is **effectively** enforced, after
  dropped entries. Shorter than what you configured means something was
  rejected; the WARN above it names it.
- `trusted_proxy` — `disabled`, `enabled (mode=filter)`, or
  `enabled (mode=depth)`, read from the same `site.network.trusted_proxy` state
  that configures the IP-privacy mount.

`host_gate: active` means the gate is comparing hosts. It does not mean the host
it compares is trustworthy: with `trusted_proxy: disabled` the detected host may
have been chosen by any peer on a private address, and the client IP behind
`network_gate` comes from `REMOTE_ADDR`. Both gates are only as good as that
line's third fact.

Also emitted at boot, each at WARN, and each only in its own case:

| Message | Means |
|---|---|
| ``Admin host allowlist DISABLED by `*` `` | `ADMIN_ALLOWED_HOSTS=*` — host gate off |
| ``Dropped `*` from site.admin.allowed_hosts: it is only honored as the sole entry`` | `*` was mixed with named hosts |
| `Ignoring unusable entries in site.admin.allowed_hosts` | some entries dropped; each named with its reason |
| `Admin host allowlist INACTIVE: no routable hostname configured` | the unset/fallback case only — see [inert](#when-the-host-gate-goes-inert) |
| `Invalid CIDR in site.admin.allowed_cidrs, skipping: …` | an unparseable CIDR entry |

There is no boot WARN for an unenforceable `ADMIN_ALLOWED_HOSTS`; that is a
[boot error](#when-boot-refuses-to-start) — the process stops before the
middleware is built. One exception exists for embedders that build the Rack app
without running config validation: the middleware then logs `Admin host
allowlist has no enforceable entry; denying both admin surfaces` and 404s both
surfaces. If you see that line, config validation did not run.

Per-request denials log at WARN with the host or IP that was refused: `Admin
surface access denied by host allowlist` and `Admin surface access denied by
network isolation`. Two distinct messages for two distinct factors — the client
cannot tell the denials apart, but the operator can.
