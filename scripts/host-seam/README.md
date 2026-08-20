# Host-seam matrix

Proxy-simulation matrix for the public-host seam — the boundary where
"the hostname the browser used" stops being the same string as
`request.host`. #4224 (tenant SSO resolved the wrong host behind a
Host-rewriting proxy) lived on that seam; #4223 exists to kill the class.

## Why local dev never caught this

The local Caddy custom-domain block does a bare `reverse_proxy 127.0.0.1:7143`.
Caddy v2 **preserves the incoming Host by default**, so on
`local-secrets1..3.afb.pet` the public host and `request.host` are always the
same string. Every consumer that keys on `request.host` looks correct.

Production does not work that way. Approximated terminates the customer's
domain, moves the real hostname into `Apx-Incoming-Host`, and rewrites `Host:`
to the origin target. There is no request you can currently make through the
local stack that tells a consumer reading the public host apart from one
reading the raw `Host` header.

That is the actual root cause of the miss — not the hook. Until the local edge
rewrites Host somewhere, this class of bug is invisible before production.

## The three lanes

| Lane          | Hosts                       | Topology                                                                           |
| ------------- | --------------------------- | ---------------------------------------------------------------------------------- |
| Preserved     | `local-secrets1..3.afb.pet` | Host passed through (existing block)                                               |
| **Rewritten** | `local-secrets4..5.afb.pet` | Host rewritten, real host in `Apx-Incoming-Host` (`caddy-approximated-lane.caddy`) |
| Headless      | `topology-probe.sh`         | eleven topologies by curl, no browser, no TLS                                      |

Register the same org's custom domain on a host from each of the first two
lanes and any custom-domain feature can be checked against both topologies. A
feature that works on lane 1 and fails on lane 2 is reading the raw Host header.

## The oracle

Every release since v0.25.0 emits two response headers from `DomainStrategy`,
unchanged:

- `O-Domain-Strategy` — `canonical` / `custom` / `invalid`
- `O-Display-Domain` — the resolved public host

That is one side of the seam. The other side is `POST /auth/sso/entra`, whose
`Location` reveals which host the tenant lookup actually keyed on. CSRF is
deliberately skipped on `/auth/sso/*`, so a bare POST is a valid probe.

**Match on the tenant id, not the IdP hostname.** The platform fallback also
redirects to `login.microsoftonline.com` — with the *platform* tenant. Only
`login.microsoftonline.com/<tenant_id>/…` proves tenant credentials were
injected, which is why `--tenant-id` must match the seeded fixture.

**The finding is the disagreement.** `O-Domain-Strategy: custom` on the same
request whose SSO lookup did not reach the tenant is the #4224 signature,
reported as `SEAM_SPLIT` — regardless of which component caused the split
(rack's `request.host`, otto's `DetectHost`, middleware order, or the hook). It
comes in two flavours, and which one you get depends on what the proxy left in
`Host:`:

- `SEAM_SPLIT(NO_CONFIG)` — the inbound target is a domain the app does not
  know, so the hook takes the tenant-fallback branch. **This is the production
  failure.** Loud.
- `SEAM_SPLIT(PLATFORM_FALLBACK)` — the inbound target *is* the canonical host,
  so the hook takes its `canonical_domain?` branch and injects platform
  credentials. The user reaches an IdP, just the wrong one. Silent unless the
  tenant id is checked — which is the whole reason it is.

Three more verdicts cover the edge and the security half:

- `SPOOF_ACCEPTED` — an untrusted client's forwarded host reached
  `O-Display-Domain`. Rack 3.2.7's `request.host` prefers
  `X-Forwarded-Host`/`Forwarded` from _any_ client, ungated by proxy trust.
- `STRATEGY_DRIFT` — the topology resolved to a classification it should not.
- T9 (`xfh-shadows-apx`) scores `ok` at `canonical` **by design**. DetectHost
  breaks on the first *syntactically* valid domain and never checks whether it
  is known, so an attacker-supplied `X-Forwarded-Host` outranks the edge's
  legitimate `Apx-Incoming-Host` and suppresses it. DomainStrategy then rejects
  the unknown domain and falls back to canonical — no impersonation, but the
  tenant's SSO silently degrades for as long as the header can be attached.
  That is a finding about the **edge**, which must strip inbound
  `X-Forwarded-Host`, not about the app.

## Running it

### Prerequisites

- `curl` (used by both harness scripts)
- `openssl` (used by `release-sweep.sh` to generate per-sweep secrets when unset)
- `podman` and pull access to `ghcr.io/onetimesecret/onetimesecret` (required for `release-sweep.sh`)

### Release gate — one version

Against anything already running (local dev server, a container, staging):

```bash
scripts/host-seam/topology-probe.sh \
  --base http://127.0.0.1:7143 \
  --canonical dev.onetime.dev \
  --custom   local-secrets1.afb.pet
```

Exit 0 means every topology matched. Non-zero means read the verdict column.
Wire this into the release checklist — it is the matrix #4223 names as the gate
for flipping its flag.

Requires the custom domain to be seeded:

```bash
HOST_SEAM_DOMAIN=local-secrets1.afb.pet bin/ots console < scripts/host-seam/seed-tenant.rb
```

Also requires:

- `TRUSTED_PROXY_ENABLED=true` (filter mode trusts loopback and RFC1918).
  Without it `DetectHost` discards every forwarded header and T3–T5 collapse to
  canonical for reasons unrelated to the bug under test.
- `ORGS_SSO_ENABLED=true` so `/auth/sso/entra` is mounted. If disabled, the
  probe reports `NO_ROUTE` (404) and the SSO seam check is not valid.

### Archaeology — which release started it

```bash
scripts/host-seam/release-sweep.sh v0.26.0 v0.26.1 v0.26.2 v0.26.3 v0.26.4 v0.26.5
```

Pulls each published image, runs it against a dedicated probe datastore
(its own valkey; never the shared 2163/2154 test datastore), seeds once, probes,
and prints the release at which each topology's verdict flipped.

Read the TSV before trusting transitions: rows marked `IMAGE_UNAVAILABLE`,
`START_FAILED`, or `NEVER_READY` mean that release was not actually probed and
cannot support a "first bad version" conclusion.

**Images, not `git bisect`.** What `request.host` returns for a given wire
request is decided by the rack version, otto's `DetectHost`, the middleware
order, and the app code _together_. A release image pins all four at the
combination that actually ran in production; bisecting the source tree against
today's `Gemfile.lock` would hold the most likely culprit fixed.

### Browser lane

Install `caddy-approximated-lane.caddy` into
`~/Projects/ops/environments/local/caddy/` and reload Caddy. It reuses the
existing `dev.metalbaum.dev+7` certificate — `local-secrets4/5` are already
SANs, so no new certs are needed. If your ops checkout lives elsewhere, update
the absolute `tls` cert/key paths in `caddy-approximated-lane.caddy` first.

## What the sweep will and won't answer for #4224

The hook itself is **not** where the regression is. `request.host` has keyed the
tenant lookup since the hook was introduced (`858d6a7fa`, #2730) and is present
unchanged in every tag from v0.25.0 through v0.26.5. So no bisect of that file
can find a "first bad version" — there isn't one.

The change has to be on the other side of the seam, in what `request.host`
_returns_. The one place the dependency set moved is **v0.26.4 → v0.26.5**,
where rack went 3.2.6 → 3.2.7 and otto went 2.6.0 → 2.9.0 in the same bump.
That is the window the sweep should interrogate first, and it is testable purely
at the container level — which is exactly what this harness does.

## SEAM_SPLIT, observed in production

The 2026-08-20 capture (`custom-domain-log.jsonl.txt`) contains the split
directly, within the same ~40ms window on `nz-por-web-02`:

```
03:38:32.589  [DetectHost] nz.metalbaum.com via HTTP_APX_INCOMING_HOST
03:38:32.590  [DomainStrategy] determined  host=secret.asi.nz  strategy=custom
03:38:32.632  [omniauth_tenant_resolution_start]  host=nz.onetime.co
03:38:32.633  [omniauth_tenant_no_config]         host=nz.onetime.co
03:38:33.129  [DetectHost] nz.onetimesecret.com via HTTP_X_ORIGINAL_HOST
```

`secret.asi.nz` is the customer's custom domain. `nz.onetime.co` is the
Approximated **inbound target** — the value the proxy left in `Host:`, and
therefore what `request.host` returned inside the hook. `DomainStrategy` said
`custom`; the tenant lookup said it had never heard of the domain. That is
`SEAM_SPLIT(NO_CONFIG)`, the exact verdict the probe emits for T3.

Two things this capture settles about the matrix itself:

- **More than one carrier is live.** One host arrives via
  `HTTP_APX_INCOMING_HOST`, another via `HTTP_X_ORIGINAL_HOST`. A harness that
  only exercised `Apx-Incoming-Host` would miss half the ingress paths, which is
  why T5–T7 cover `X-Forwarded-Host`, `X-Original-Host` and RFC 7239
  `Forwarded` as well.
- **The inbound target is a real platform host**, not a synthetic one. When it
  is non-canonical (`nz.onetime.co`) the failure is loud; T8 covers the case
  where it happens to be the canonical host and the failure goes quiet instead.

## When to run

1. **You changed host/domain logic and want a quick gate now** → run `topology-probe.sh` against your running app.
2. **`topology-probe.sh` shows non-`ok` verdicts** → first verify setup (`ORGS_SSO_ENABLED=true`, `TRUSTED_PROXY_ENABLED=true`, seeded domain).
3. **You need “which release introduced this?”** → run `release-sweep.sh` with target tags.
4. **Sweep output includes `IMAGE_UNAVAILABLE` / `START_FAILED` / `NEVER_READY`** → do not trust transition conclusions until resolved.
5. **You need browser-path parity with production ingress behavior** → enable `caddy-approximated-lane.caddy` and compare preserved vs rewritten lanes.
