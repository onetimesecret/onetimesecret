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
non-ASCII name) **404s both admin surfaces** rather than quietly serving admin
everywhere, and says so at boot. See [When the allowlist cannot be
enforced](#when-the-allowlist-cannot-be-enforced).

If the app runs behind a reverse proxy that forwards the public hostname in a
header (`X-Forwarded-Host`, `Apx-Incoming-Host`, `X-Original-Host`,
`Forwarded`) rather than rewriting `Host`, you **must** configure
`site.network.trusted_proxy` **with the proxy's own address ranges in
`cidrs`** — otherwise the admin gate refuses the forwarded host and both
surfaces 404. Filter mode with no explicit CIDRs trusts every private-network
peer as a proxy, which restores exactly the forwarded-host spoofing the
provenance rule exists to block. See [Behind a reverse proxy or load
balancer](#behind-a-reverse-proxy-or-load-balancer--required-for-both-gates).

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

### Route-level network requirements

Otto routes can declare `network=admin` when an endpoint must not inherit the
network gate's opt-in default. Such a route returns `404` unless all of these are
true:

1. `ADMIN_ALLOWED_HOSTS` explicitly names an enforceable admin hostname.
2. `ADMIN_ALLOWED_CIDRS` contains at least one parseable range.
3. The request passes both allowlists.

The canonical-host fallback does not satisfy an explicit route requirement, and
`ADMIN_ALLOWED_HOSTS=*` disables the host gate, so it does not satisfy one
either. Routes without `network=admin` retain the general Colonel behavior
described above. The proxy-header diagnostic is the first route using this
requirement; see [Proxy header diagnostic](proxy-header-diagnostic.md).

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
  and if it was the *only* entry, both admin surfaces 404.
- **Patterns are not supported.** `*.example.com` matches nothing: it is dropped
  and named in a boot WARN, and a list of nothing but patterns 404s both admin
  surfaces. List each hostname explicitly.
- **A nil or unresolvable detected host is a 404** while the gate is active.
- **A forwarded host from an untrusted peer is a 404** while the gate is active
  — see [Behind a reverse proxy or load
  balancer](#behind-a-reverse-proxy-or-load-balancer--required-for-both-gates).
- `ADMIN_ALLOWED_HOSTS=*` disables the host gate, logged at WARN on boot. The
  CIDR gate is unaffected. **A `*` anywhere in the list turns the gate off** —
  a `*` beside named hosts does not enforce those hosts, it ignores them (and
  names them in a second WARN). Remove the `*` to enforce them.
- **A percent-encoded spelling of an admin path is still an admin path.**
  `/%63olonel` and `/colonel%2Fsettings` are gated exactly like `/colonel`,
  because that is what the router serves them as.
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
that was set but cannot be enforced does not go inert — it denies.

### When the allowlist cannot be enforced

If `ADMIN_ALLOWED_HOSTS` is **set and non-empty** but no entry survives — every
entry is an IP address, a `*.` pattern, a non-ASCII name, or not a hostname at
all — the host gate stays **active with an empty allowlist**: `/colonel` and
`/api/colonel` return 404 to every request, on every hostname. The rest of the
app is untouched. Boot logs a WARN naming each entry and why:

```
ADMIN_ALLOWED_HOSTS (site.admin.allowed_hosts) names no hostname the admin host
gate could ever match, so /colonel and /api/colonel return 404 to EVERY request:
"127.0.0.1": not a routable hostname — localhost forms and IP literals are never
detected as a host. Set it to a routable hostname the deployment answers on
(ADMIN_ALLOWED_HOSTS=admin.example.com), unset it entirely to allow the canonical
host only (on a localhost or bare-IP install that self-disables the gate
instead), or set it to * to disable the host gate deliberately.
```

Denying is deliberate. Every one of these values is an operator writing an
allowlist in order to **restrict** the admin surfaces; disabling the gate on a
typo would do the opposite of what was asked and serve `/colonel` on every
hostname the app answers on. The three ways out are the three in the message:
name a routable hostname, unset it, or ask for the gate to be off with
`ADMIN_ALLOWED_HOSTS=*`. Unsetting restores the canonical-anchor fallback,
which restricts to the canonical hosts only when an anchor (`DEFAULT_DOMAIN` /
`HOST`) is a routable hostname. On a localhost or bare-IP install the fallback
has nothing to anchor on, so unsetting **self-disables the gate** with a boot
WARN ([inert](#when-the-host-gate-goes-inert)) — it is not a hardening step
there.

**This does not stop the boot** (it did until #4062 shipped). The admin surfaces
are already fail-closed for this config, so aborting the process would take the
public site, the API and the health endpoints down over an admin-console-only
typo — an `ADMIN_ALLOWED_HOSTS=10.0.0.0/8` mixup with the adjacent
`ADMIN_ALLOWED_CIDRS` key would be a full outage. Contrast `LINK_DOMAINS`
(#4063), which *does* fail the boot: it has no fail-closed runtime backstop, so
there the process has to stop.

Common triggers:

| Value | Result |
|---|---|
| `ADMIN_ALLOWED_HOSTS=127.0.0.1` / `localhost` | boots with a WARN; both admin surfaces 404 — never detected as a host |
| `ADMIN_ALLOWED_HOSTS=*.example.com` | boots with a WARN; both admin surfaces 404 — patterns are not supported |
| `ADMIN_ALLOWED_HOSTS=ünïcode.example` | boots with a WARN; both admin surfaces 404 — supply the `xn--` form |
| `ADMIN_ALLOWED_HOSTS=*.example.com,admin.example.com` | boots; the pattern is dropped with a WARN, `admin.example.com` is enforced |
| `ADMIN_ALLOWED_HOSTS=*` | boots; host gate off, WARN |
| `ADMIN_ALLOWED_HOSTS=*,admin.example.com` | boots; host gate **off** (the `*` wins), both entries named in a WARN |
| unset / empty | boots; canonical anchors, or inert (above) |

Partial failures change nothing: as long as **one** entry is enforceable, the
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

### CIDR precision and privacy masking

Client IPs are **privacy-masked before any middleware sees them** — IP masking
is on for every deployment, including direct-connect ones. IPv4 clients arrive
with the last octet zeroed (an effective `/24`), IPv6 clients at an effective
`/48`. Single-host entries — `10.0.0.5/32` for your VPN host, a Tailscale
node's `/128` — and anything else narrower than `/24` (IPv4) or `/48` (IPv6)
therefore **require the true-IP match support**: the verdict-only matcher the
IP-privacy layer installs, which answers allowlist membership against the real
client address without the unmasked address ever landing in the request
environment. Where the gate matches through that support, full `/32`–`/128`
precision works.

Where the matcher is absent from the request environment, the gate falls back
to comparing the resolved client IP directly. The privacy layer installs the
matcher on every path that masks — the two travel together — so a stack
missing the matcher is one that never masked, and the fallback still compares
the full-precision address. Fine entries misbehave only in a stack that masks
the IP without installing the matcher, which this stack does not produce; if
you must plan for one, keep entries at `/24` or coarser for IPv4 and `/48` or
coarser for IPv6 — the ranges in the example above already are. Background in
#3912.

## Behind a reverse proxy or load balancer — required for both gates

Each gate reads an input a proxy can rewrite, and each resolves that input the
same way the rest of the stack does:

- The **network** gate matches the **trusted-proxy-resolved** client IP — the
  same value used for ban checks, sessions and audit attribution, read from
  `env['otto.client_ip']`, which the universal IP-privacy middleware sets from
  `site.network.trusted_proxy`. A **raw `X-Forwarded-For` header cannot bypass
  the allowlist** — that is the point. **That value is also privacy-masked**:
  IPv4 arrives zeroed to its `/24` and IPv6 to its `/48`, so an entry finer
  than that needs the true-IP match support — see [CIDR precision and privacy
  masking](#cidr-precision-and-privacy-masking).
- The **host** gate matches the host `Rack::DetectHost` validated, and applies
  one extra check of its own: a forwarded host header (`X-Forwarded-Host`,
  `Apx-Incoming-Host`, `X-Original-Host`, `Forwarded`) is accepted **only** when
  `env['otto.via_trusted_proxy']` is true — i.e. `site.network.trusted_proxy` is
  configured and this peer passed it. Otherwise the forwarded host must agree
  with the `Host` header, or the request is refused. See [Forwarded hosts and
  the admin gate](#forwarded-hosts-and-the-admin-gate).

Consequently, if the app runs behind a reverse proxy, ingress, or load balancer,
you **must** also configure `site.network.trusted_proxy` (see `.env.reference`,
`TRUSTED_PROXY_*`) — and name the proxy's own address ranges in `cidrs`
(`TRUSTED_PROXY_CIDRS`) explicitly. Filter mode with no explicit CIDRs trusts
every private-network peer as a proxy, which restores exactly the
forwarded-host spoofing the provenance rule exists to block. Without
`trusted_proxy` at all, every request resolves to the proxy's own hop IP, and
either all requests are allowed (if that hop is inside the allowlist) or all
are denied. Example:

```yaml
site:
  network:
    trusted_proxy:
      enabled: true
      mode: filter          # depth mode is broken, see #4024
      cidrs:
        - 10.0.0.5/32       # the proxy's own address, not its whole subnet
  admin:
    allowed_cidrs:
      - 100.64.0.0/10
```

**With `trusted_proxy` disabled (the default), host detection falls back to a
legacy heuristic**: any peer connecting from a private or loopback address is
trusted to set a forwarded host header. That keeps single-container installs
behind a local proxy working, but it also means anything able to open a
connection from a private address — another container on the same network, an
SSRF egress — can choose the host the app sees (#4024). The client IP behind the
CIDR gate has the same dependency: with no trusted proxy declared it is resolved
from `REMOTE_ADDR`. Configure `trusted_proxy` — with the proxy's explicit
`cidrs` — on any deployment where a private-address peer is reachable.

Because that state qualifies both gates, it is reported on the same boot line
they are — `trusted_proxy: disabled` sitting next to `host_gate: active` is the
combination to look for. See [Verifying](#verifying).

### Forwarded hosts and the admin gate

The admin host gate does not rely on that heuristic. It accepts a detected host
only when one of these holds:

1. `env['otto.via_trusted_proxy']` is **true** — `site.network.trusted_proxy` is
   configured and this peer passed it; or
2. the request carries **no** forwarded host header at all; or
3. it carries one, but the detected host is **the same** as what the `Host`
   header alone would have produced — the header changed nothing.

Anything else is a 404 on both surfaces, logged as `Admin surface access denied:
forwarded host from an untrusted peer`.

Without this, on any install with `trusted_proxy` unset, a request to a tenant
custom domain carrying `X-Forwarded-Host: <your canonical host>` would reach the
admin console — the heuristic would trust it because the request arrived from
the proxy's private address.

The gate deliberately does **not** fall back to the `Host` header when it
refuses a forwarded one. In the topology this defends (Approximated-style
ingress with `trusted_proxy` unset) `Host` carries the *origin's* hostname —
typically the canonical one, which is on the allowlist — while the tenant
domain rides in `Apx-Incoming-Host`. Falling back would admit exactly the
requests this exists to refuse.

**If both admin surfaces started 404ing after this landed**, and your proxy
forwards the public hostname in a header rather than rewriting `Host`, that is
this rule. Two ways out:

```yaml
# Preferred — it is also what the CIDR gate, ban checks, sessions and audit
# attribution all need to be correct. List the proxy's own addresses in
# `cidrs`: filter mode with no explicit CIDRs trusts every private-network
# peer as a proxy, which restores exactly the forwarded-host spoofing this
# rule exists to block.
site:
  network:
    trusted_proxy:
      enabled: true
      mode: filter
      cidrs:
        - 10.0.0.5/32     # the proxy's own address
```

```bash
# Or turn the host gate off entirely.
ADMIN_ALLOWED_HOSTS=*
```

### nginx: the default `proxy_pass` erases the host

The other proxy-shaped 404: nginx rewrites `Host` to the upstream address
unless told otherwise, so a stock `proxy_pass http://127.0.0.1:3000;` hands the
app `Host: 127.0.0.1:3000` — an IP literal. `Rack::DetectHost` emits no host
for that, and while the host gate is active a request with no detected host is
denied, logged per request as `Admin surface access denied: no host could be
detected for this request`. No allowlist entry can fix it, because the
allowlist is never consulted. Forward the original host instead:

```nginx
location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;                    # keep the client's hostname
    proxy_set_header X-Forwarded-For $remote_addr;  # overwrite, never append
}
```

(Caddy's `reverse_proxy` forwards `Host` unchanged by default, so it does not
have this failure mode.)

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
- `site.network.trusted_proxy` must be configured correctly — enabled, filter
  mode, the proxy's own address ranges named in `cidrs` — or **both** gates
  read attacker-influenceable inputs: filter mode with no explicit CIDRs
  trusts every private-network peer as a proxy, which restores exactly the
  forwarded-host spoofing the provenance rule exists to block. Depth mode is
  currently broken (#4024) — do not use it.

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
  `*.example.com`): the process starts and logs a WARN; `/colonel` and
  `/api/colonel` return 404 on every hostname. Everything else is served
  normally.
- With `ADMIN_ALLOWED_CIDRS` set to something unparseable (every entry
  malformed): same shape — the process starts, logs an error, and both admin
  surfaces 404 from every IP. An **empty** `ADMIN_ALLOWED_CIDRS` still means "no
  network gate"; that distinction is the point.
- A spoofed `X-Forwarded-For: <allowed-ip>` from an untrusted origin does **not**
  bypass the CIDR allowlist, and a spoofed `X-Forwarded-Host` /
  `Apx-Incoming-Host` does **not** bypass the host allowlist — for the host gate
  a forwarded header counts only from a peer `site.network.trusted_proxy`
  vouched for, never from the private-address heuristic.
- A percent-encoded admin path (`/%63olonel`, `/colonel%2Fsettings`) returns the
  same 404 as `/colonel` on a denied host or from a denied IP.

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

That line is emitted **once per process**, not once per mounted app. The
middleware is constructed for each of the app's mounts, all from the same
config; every message below is deduplicated the same way, so a repeated line
means a genuinely different posture, not a second mount.

Also emitted at boot, each only in its own case:

| Message | Level | Means |
|---|---|---|
| ``Admin host allowlist DISABLED by `*` `` | WARN | `ADMIN_ALLOWED_HOSTS` contains `*` — host gate off |
| ``Ignoring every other entry in site.admin.allowed_hosts: `*` disables the host gate`` | WARN | `*` was listed beside other entries; those entries do nothing |
| `Ignoring unusable entries in site.admin.allowed_hosts` | WARN | some entries dropped; each named with its reason |
| `Admin host allowlist INACTIVE: no routable hostname configured` | WARN | the unset/fallback case only — see [inert](#when-the-host-gate-goes-inert) |
| `Admin host allowlist has no enforceable entry; denying both admin surfaces` | WARN | an explicit list where nothing survived — see [above](#when-the-allowlist-cannot-be-enforced) |
| `Invalid CIDR in site.admin.allowed_cidrs, skipping: …` | WARN | an unparseable CIDR entry, with others still usable |
| `Admin CIDR allowlist has no usable range; denying both admin surfaces` | ERROR | a configured `ADMIN_ALLOWED_CIDRS` where **no** entry parsed |
| `Cannot read site.admin.allowed_hosts; denying both admin surfaces` | ERROR | the config could not be read at all (not the same as unset) |
| `Cannot read site.admin.allowed_cidrs; denying both admin surfaces` | ERROR | ditto, for the CIDR list |

`Onetime::Config` emits the operator-facing diagnostics at boot too: the
unenforceable-`ADMIN_ALLOWED_HOSTS` message quoted
[above](#when-the-allowlist-cannot-be-enforced), and a matching WARN for an
`ADMIN_ALLOWED_CIDRS` with unparseable entries — naming the entries, whether
any survive to enforce, and the way out. The reason arrives with the startup
log rather than only on the first admin request.

Per-request denials log at WARN with the host or IP that was refused. Four
distinct messages for four distinct refusals — the client cannot tell the
denials apart, but the operator can:

| Message | Means |
|---|---|
| `Admin surface access denied by host allowlist` | a host was detected and is not on the list |
| `Admin surface access denied: no host could be detected for this request` | `Rack::DetectHost` emitted nothing — a bare-IP or `localhost` `Host:` header, or a malformed name. The allowlist was never consulted, so no entry in it could have helped |
| `Admin surface access denied: forwarded host from an untrusted peer` | see [Forwarded hosts and the admin gate](#forwarded-hosts-and-the-admin-gate) |
| `Admin surface access denied by network isolation` | the client IP is outside `allowed_cidrs` |

The second one is the line to look for if you set `ADMIN_ALLOWED_HOSTS` to an IP
address: no hostname you write into the allowlist can match a request that has
no detected host. Behind nginx, the usual cause is a `proxy_pass` without
`proxy_set_header Host $host;` — see [nginx: the default `proxy_pass` erases
the host](#nginx-the-default-proxy_pass-erases-the-host). Reach admin on a
routable hostname, or set `ADMIN_ALLOWED_HOSTS=*` to turn the host gate off.
