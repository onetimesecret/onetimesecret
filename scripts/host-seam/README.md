# Host-seam matrix

Proxy-simulation matrix for the **public-host seam**: the boundary where
"the hostname the browser used" stops being the same string as `request.host`.

Issue #4224 (tenant SSO resolved the wrong host behind a Host-rewriting proxy)
lived on this seam. Issue #4223 adds this matrix to prevent that class of
regression.

## What this harness checks

The matrix compares two readings from the same request:

1. **DomainStrategy side** (response headers):
   - `O-Domain-Strategy` (`canonical` / `custom` / `invalid`)
   - `O-Display-Domain` (resolved public host)
2. **Tenant-lookup side** (`POST /auth/sso/entra` redirect `Location`):
   - whether SSO resolved tenant credentials (`.../login.microsoftonline.com/<tenant_id>/...`)
   - or fell back / failed (`PLATFORM_FALLBACK`, `sso_not_configured`, etc.)

The finding is the disagreement between those two sides.

## Why local dev missed this class

The local Caddy custom-domain block uses `reverse_proxy 127.0.0.1:7143`.
Caddy v2 preserves incoming `Host` by default, so on
`local-secrets1..3.afb.pet` the public host and `request.host` are the same
string. Consumers that read `request.host` appear correct.

Production ingress (Approximated) behaves differently:

- rewrites `Host` to the origin target
- carries the browser hostname in `Apx-Incoming-Host`

Until local edge rewrites `Host` somewhere, this bug class is invisible before
production.

## The three lanes

| Lane          | Hosts                       | Topology                                                                           |
| ------------- | --------------------------- | ---------------------------------------------------------------------------------- |
| Preserved     | `local-secrets1..3.afb.pet` | Host passed through (existing block)                                               |
| **Rewritten** | `local-secrets4..5.afb.pet` | Host rewritten, real host in `Apx-Incoming-Host` (`caddy-approximated-lane.caddy`) |
| Headless      | `topology-probe.sh`         | 11 curl topologies, no browser, no TLS                                             |

Register the same org custom domain on a host from the first two lanes. Any
feature that passes lane 1 and fails lane 2 is reading raw `Host`.

## Oracle and verdicts

### Why tenant-id matching matters

Both tenant success and platform fallback redirect to
`login.microsoftonline.com`. Match the **tenant id in the path**, not only the
IdP hostname. That is why `topology-probe.sh --tenant-id` must match the seeded
fixture.

### Verdict meanings

- `ok` — topology matched expectations.
- `SEAM_SPLIT(NO_CONFIG)` — `O-Domain-Strategy: custom` but tenant lookup ended
  at `sso_not_configured` on the same request. Loud failure. This is the
  production #4224 shape.
- `SEAM_SPLIT(PLATFORM_FALLBACK)` — `O-Domain-Strategy: custom` but SSO used
  platform credentials (`canonical_domain?` branch). Quiet failure unless
  tenant id is checked.
- `SPOOF_ACCEPTED` — untrusted forwarded host reached `O-Display-Domain`.
- `STRATEGY_DRIFT(...)` — DomainStrategy classification differed from expected
  for that topology.

Special case: T9 (`xfh-shadows-apx`) is expected to resolve `canonical` **by
design**. `X-Forwarded-Host` can outrank `Apx-Incoming-Host` in carrier
precedence; app fallback stays canonical, but tenant SSO can be denied until the
edge strips inbound `X-Forwarded-Host`.

## Running it

Run commands from repo root.

### Prerequisites

- `curl` (both scripts)
- `openssl` (`release-sweep.sh` generates per-sweep secrets when unset)
- `podman` and pull access to `ghcr.io/onetimesecret/onetimesecret`
  (`release-sweep.sh`)

### Release gate (one running version)

Against an already-running app (local server, container, or staging):

```bash
scripts/host-seam/topology-probe.sh \
  --base http://127.0.0.1:7143 \
  --canonical dev.onetime.dev \
  --custom local-secrets1.afb.pet
```

Exit `0` means all topologies matched; non-zero means read `verdict`.

Seed required fixture first:

```bash
HOST_SEAM_DOMAIN=local-secrets1.afb.pet bin/ots console < scripts/host-seam/seed-tenant.rb
```

Also required for valid SSO seam checks:

- `TRUSTED_PROXY_ENABLED=true` (filter mode trusts loopback/RFC1918). Without
  it, `DetectHost` drops forwarded carriers and T3–T5 collapse to canonical for
  unrelated reasons.
- `ORGS_SSO_ENABLED=true` so `/auth/sso/entra` is mounted. If disabled, probe
  SSO results become `NO_ROUTE` (404), and seam verdicts are not meaningful.

### Archaeology (which release started it)

```bash
scripts/host-seam/release-sweep.sh v0.26.0 v0.26.1 v0.26.2 v0.26.3 v0.26.4 v0.26.5-rc1 v0.26.5-rc2 v0.26.5
```

The sweep:

- pulls each published release image
- runs each against a dedicated probe datastore
- seeds once (idempotent fixture)
- runs `topology-probe.sh --tsv`
- reports verdict transitions per topology

Read TSV status rows before drawing "first bad version" conclusions:
`IMAGE_UNAVAILABLE`, `START_FAILED`, `NEVER_READY` mean that tag was not
actually probed.

Output includes:

- per-release matrix on stderr
- full TSV: `tmp/host-seam/sweep-<timestamp>.tsv`
- transition report at the end

### Browser rewritten lane

Install `scripts/host-seam/caddy-approximated-lane.caddy` into:

`~/Projects/ops/environments/local/caddy/`

Then reload Caddy.

This lane reuses `dev.metalbaum.dev+7`; `local-secrets4/5` are already SANs. If
your ops checkout path differs, update absolute `tls` cert/key paths in
`caddy-approximated-lane.caddy` first.

## What the sweep can and cannot answer for #4224

The regression is not in the hook itself. The tenant lookup has keyed on
`request.host` since hook introduction (`858d6a7fa`, #2730), unchanged across
v0.25.0..v0.26.5.

The likely change is in what `request.host` returns for the wire request.
Dependency movement is concentrated at **v0.26.4 -> v0.26.5** (rack 3.2.6 ->
3.2.7 and otto 2.6.0 -> 2.9.0), so that window is the highest-value first
sweep target.

Use release images, not `git bisect`, because runtime behavior depends on rack,
otto `DetectHost`, middleware order, and app code together.

## Production signature (2026-08-20 capture)

`custom-domain-log.jsonl.txt` contains this split on `nz-por-web-02`:

```text
03:38:32.589  [DetectHost] nz.metalbaum.com via HTTP_APX_INCOMING_HOST
03:38:32.590  [DomainStrategy] determined  host=secret.asi.nz  strategy=custom
03:38:32.632  [omniauth_tenant_resolution_start]  host=nz.onetime.co
03:38:32.633  [omniauth_tenant_no_config]         host=nz.onetime.co
03:38:33.129  [DetectHost] nz.onetimesecret.com via HTTP_X_ORIGINAL_HOST
```

Interpretation:

- `DomainStrategy` classified request as `custom` (`secret.asi.nz`)
- tenant lookup keyed on rewritten inbound target (`nz.onetime.co`)
- result is `SEAM_SPLIT(NO_CONFIG)` (probe T3 shape)

The same capture also shows multiple live carriers (`HTTP_APX_INCOMING_HOST`
and `HTTP_X_ORIGINAL_HOST`), which is why the matrix covers
`Apx-Incoming-Host`, `X-Forwarded-Host`, `X-Original-Host`, and RFC 7239
`Forwarded`.

## When to run

1. You changed host/domain logic and need a fast gate: run `topology-probe.sh`.
2. Probe shows non-`ok`: verify setup (`ORGS_SSO_ENABLED=true`,
   `TRUSTED_PROXY_ENABLED=true`, seeded custom domain).
3. You need "which release introduced this": run `release-sweep.sh` on target
   tags.
4. Sweep has `IMAGE_UNAVAILABLE` / `START_FAILED` / `NEVER_READY`: do not trust
   transition conclusions yet.
5. You need browser-path parity with rewritten ingress: enable
   `caddy-approximated-lane.caddy` and compare preserved vs rewritten lanes.
