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

| Lane | Hosts | Topology |
|---|---|---|
| Preserved | `local-secrets1..3.afb.pet` | Host passed through (existing block) |
| **Rewritten** | `local-secrets4..5.afb.pet` | Host rewritten, real host in `Apx-Incoming-Host` (`caddy-approximated-lane.caddy`) |
| Headless | `topology-probe.sh` | seven topologies by curl, no browser, no TLS |

Register the same org's custom domain on a host from each of the first two
lanes and any custom-domain feature can be checked against both topologies. A
feature that works on lane 1 and fails on lane 2 is reading the raw Host header.

## The oracle

Every release since v0.25.0 emits two response headers from `DomainStrategy`,
unchanged:

- `O-Domain-Strategy` — `canonical` / `custom` / `invalid`
- `O-Display-Domain` — the resolved public host

That is one side of the seam. The other side is `POST /auth/sso/entra`, whose
`Location` reveals which host the tenant lookup actually keyed on
(`login.microsoftonline.com/<tenant_id>/…` vs `auth_error=sso_not_configured`).
CSRF is deliberately skipped on `/auth/sso/*`, so a bare POST is a valid probe.

**The finding is the disagreement.** `O-Domain-Strategy: custom` together with
`sso_not_configured` on the *same request* is the #4224 signature, and it is
what the probe reports as `SEAM_SPLIT` — regardless of which component caused
the split (rack's `request.host`, otto's `DetectHost`, middleware order, or the
hook).

Two verdicts cover the security half:

- `SPOOF_ACCEPTED` — an untrusted client's forwarded host reached
  `O-Display-Domain`. Rack 3.2.7's `request.host` prefers
  `X-Forwarded-Host`/`Forwarded` from *any* client, ungated by proxy trust.
- `STRATEGY_DRIFT` — the topology resolved to a classification it should not.

## Running it

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

Also requires `TRUSTED_PROXY_ENABLED=true` (filter mode trusts loopback and
RFC1918). Without it `DetectHost` discards every forwarded header and T3–T5
collapse to canonical for reasons unrelated to the bug under test.

### Archaeology — which release started it

```bash
scripts/host-seam/release-sweep.sh v0.26.0 v0.26.1 v0.26.2 v0.26.3 v0.26.4 v0.26.5
```

Pulls each published image, runs it against a dedicated probe datastore
(its own valkey; never the shared 2163/2154 test datastore), seeds once, probes,
and prints the release at which each topology's verdict flipped.

**Images, not `git bisect`.** What `request.host` returns for a given wire
request is decided by the rack version, otto's `DetectHost`, the middleware
order, and the app code *together*. A release image pins all four at the
combination that actually ran in production; bisecting the source tree against
today's `Gemfile.lock` would hold the most likely culprit fixed.

### Browser lane

Install `caddy-approximated-lane.caddy` into
`~/Projects/ops/environments/local/caddy/` and reload Caddy. It reuses the
existing `dev.metalbaum.dev+7` certificate — `local-secrets4/5` are already
SANs, so no new certs are needed.

## What the sweep will and won't answer for #4224

The hook itself is **not** where the regression is. `request.host` has keyed the
tenant lookup since the hook was introduced (`858d6a7fa`, #2730) and is present
unchanged in every tag from v0.25.0 through v0.26.5. So no bisect of that file
can find a "first bad version" — there isn't one.

The change has to be on the other side of the seam, in what `request.host`
*returns*. The one place the dependency set moved is **v0.26.4 → v0.26.5**,
where rack went 3.2.6 → 3.2.7 and otto went 2.6.0 → 2.9.0 in the same bump.
That is the window the sweep should interrogate first, and it is testable purely
at the container level — which is exactly what this harness does.

One caveat worth settling before trusting any bisect: the captured production
log (`custom-domain-log.jsonl.txt`) shows `omniauth_tenant_resolution_start`
with `host: nz.onetime.co` — a custom domain, **not** a rewritten origin
authority — followed by `omniauth_tenant_no_config`. That is not the pure
Host-rewrite story. Either that request took a different path than the one the
fix addresses, or the failure has a second cause (a missing/mis-keyed
`SsoConfig` for that domain). Reproduce the *observed* symptom on the rewritten
lane before reading the sweep as the whole answer.
