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
- carries the browser hostname in `Apx-Incoming-Host`, which the edge in front
  of the app translates into `X-Forwarded-Host` (#4384)

Until local edge rewrites `Host` somewhere, this bug class is invisible before
production.

## The three lanes

| Lane          | Hosts                       | Topology                                                                          |
| ------------- | --------------------------- | --------------------------------------------------------------------------------- |
| Preserved     | `local-secrets1..3.afb.pet` | Host passed through (existing block)                                              |
| **Rewritten** | `local-secrets4..5.afb.pet` | Host rewritten, real host in `X-Forwarded-Host` (`caddy-approximated-lane.caddy`) |
| Headless      | `bin/host-seam probe`       | 12 curl topologies, no browser, no TLS                                            |

Register the same org custom domain on a host from the first two lanes. Any
feature that passes lane 1 and fails lane 2 is reading raw `Host`.

## Oracle and verdicts

### Why tenant-id matching matters

Both tenant success and platform fallback redirect to
`login.microsoftonline.com`. Match the **tenant id in the path**, not only the
IdP hostname. That is why `bin/host-seam probe --tenant-id` must match the seeded
fixture.

### Verdict meanings

- `ok` — topology matched expectations.
- `SEAM_SPLIT(NO_CONFIG)` — `O-Domain-Strategy: custom` but tenant lookup ended
  at `sso_not_configured` on the same request. Loud failure. This is the
  production #4224 shape.
- `SEAM_SPLIT(PLATFORM_FALLBACK)` — `O-Domain-Strategy: custom` but SSO used
  platform credentials (`canonical_domain?` branch). Quiet failure unless
  tenant id is checked.
- `SPOOF_ACCEPTED` — the evil host reached `O-Display-Domain` through a
  carrier the app does not read (`Apx-Incoming-Host`, a comma-joined
  `X-Forwarded-Host`). A single `X-Forwarded-Host` from the trusted probe
  source is the carrier the app selects, so T9 and T10 display the evil host
  and are graded on strategy alone.
- `STRATEGY_DRIFT(...)` — DomainStrategy classification differed from expected
  for that topology. On every custom row at once, it usually means `--custom`
  is not a registered CustomDomain.
- `FIXTURE_MISSING` — the direct-request control (Host set to `--custom`, no
  forwarded headers, hence no seam) answered `sso_not_configured`, so no
  enabled SsoConfig exists for `--custom`. SSO seam verdicts are
  uninterpretable in this state; seed with `seed-tenant.rb` and rerun. Header
  columns remain valid.
- `UNTESTABLE(strategy_control)` — the same direct request did not resolve
  `O-Domain-Strategy: custom`, so the strategy side of the seam cannot answer
  at all: either `--custom` is not a registered CustomDomain, or the domains
  feature is off in the app under test (`DOMAINS_ENABLED` defaults to false).
  All strategy/seam verdicts are suppressed — including the vacuous `ok` that
  rows expecting `canonical` would otherwise report with `O-Display-Domain`
  pinned to canonical.
  The warning above the table says which of the two causes it is.

Special case: T9 (`xfh-shadows-apx`) and T10 (`xfh-spoof`) are expected to
resolve `invalid`. `X-Forwarded-Host` is the one forwarded carrier the app
reads from a trusted peer (`FORWARDED_HEADERS` in `lib/middleware/detect_host.rb`),
and `Apx-Incoming-Host` beside it in T9 is not read. The unregistered evil host
becomes the display domain and classifies `invalid`, so it cannot impersonate
a tenant, but tenant SSO can be denied until the edge overwrites inbound
`X-Forwarded-Host`. This describes what the code does and what matrix spec
rows F06 and F07 pin; no ADR records it as a decision.

T3, T6 and T12 changed expectation with #4384: `Apx-Incoming-Host`,
`X-Original-Host` and a comma-separated `X-Forwarded-Host` are not read, so
those rows resolve on `Host`, as does T7 (`Forwarded` is not read). What they
expect follows the origin:

- no `--origin` (the default `origin-target.internal`): `invalid`.
- `--origin` naming the same host as `--canonical`: `canonical`. Case, a port
  and a trailing dot are ignored in that comparison.
- any other `--origin`: whatever a direct request carrying only
  `Host: <origin>` resolves to. The probe sends that request first and prints
  the result. This covers a subdomain of the canonical host (`www.`), a second
  canonical host and a registered custom domain, none of which can be
  classified from the name. A carrier that is read still shows as drift,
  because the row then differs from what the bare `Host` resolved to.
  T8 moved its carrier to `X-Forwarded-Host` and still expects `custom`. A release
  before #4384 reports T3, T6 and T12 as mismatches.

## Files

| File                     | Role                                                                   |
| ------------------------ | ---------------------------------------------------------------------- |
| `bin/host-seam`          | entry point (ADR-042): `probe`, `sweep`                                |
| `topologies.psv`         | the matrix: one row per topology with its expected strategy. Data only |
| `topology-lib.sh`        | matrix loader, origin expectation, spoof predicate                     |
| `topology-probe.sh`      | sends the matrix with curl and grades the answers                      |
| `release-sweep.sh`       | runs the probe against published release images                        |
| `seed-tenant.rb`         | fixture for the SSO column                                             |
| `tests/topology-test.sh` | loader, origin expectation, and the probe against a stand-in curl      |

The probe needs a running app, so it does not run in CI. Two things do:

- `apps/web/auth/spec/integration/full/host_proxy_matrix_spec.rb` reads
  `topologies.psv`, sends every row through the mounted stack and asserts the
  expected strategy and the spoof predicate. An expectation in the matrix that
  the application does not meet fails that spec.
- `tests/topology-test.sh` runs with `bin/testsuite run`.

## Running it

Run commands from repo root.

### Prerequisites

- `curl` (both scripts)
- `openssl` (`release-sweep.sh` generates per-sweep secrets when unset)
- `podman` and pull access to `ghcr.io/onetimesecret/onetimesecret`
  (`release-sweep.sh`)

### Release gate (one running version)

**Seed the fixture first.** The SSO column is only meaningful for a domain
that has an enabled SsoConfig; `--custom` must be _that_ domain and
`--tenant-id` must match its seeded tenant id (probe default matches the seed
default). A registered custom domain without an SsoConfig makes the probe
report `FIXTURE_MISSING` on every custom-strategy row:

```bash
HOST_SEAM_DOMAIN=local-secrets1.afb.pet bin/ots console < tools/host-seam/seed-tenant.rb
```

Then, against an already-running app (local server, container, or staging):

```bash
bin/host-seam probe \
  --base http://127.0.0.1:7143 \
  --canonical dev.onetime.dev \
  --custom local-secrets1.afb.pet
```

Exit `0` means all topologies matched; non-zero means read `verdict`.

Also required for valid SSO seam checks:

- `DOMAINS_ENABLED=true` — the domains feature defaults OFF. Without it
  `DomainStrategy` classifies every request canonical, the strategy side of
  the seam is inert, and the probe reports `UNTESTABLE(strategy_control)`.
  (`release-sweep.sh` sets this for its containers.)
- `TRUSTED_PROXY_ENABLED=true` (filter mode trusts loopback/RFC1918), so the
  probe source is trusted explicitly. With no proxy trust configured, the
  current `DetectHost` still honours `X-Forwarded-Host` from a loopback or
  private peer and from no other. Whenever the probe source is not trusted,
  `X-Forwarded-Host` is dropped, every row resolves on `Host`, and T4, T5, T8
  and T10 drift for reasons unrelated to the seam.
- `ORGS_SSO_ENABLED=true` so `/auth/sso/entra` is mounted. If disabled, probe
  SSO results become `NO_ROUTE` (404), and seam verdicts are not meaningful.

### Archaeology (which release started it)

```bash
bin/host-seam sweep v0.26.0 v0.26.1 v0.26.2 v0.26.3 v0.26.4 v0.26.5-rc1 v0.26.5-rc2 v0.26.5
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

Install `tools/host-seam/caddy-approximated-lane.caddy` into:

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
- result is `SEAM_SPLIT(NO_CONFIG)` (probe T5 shape; T3 at the time of the capture)

The same capture also shows multiple live carriers (`HTTP_APX_INCOMING_HOST`
and `HTTP_X_ORIGINAL_HOST`), which is why the matrix covers
`Apx-Incoming-Host`, `X-Forwarded-Host`, `X-Original-Host`, and RFC 7239
`Forwarded`. Since #4384 only `X-Forwarded-Host` is read; the other three are
sent as controls.

## Real-proxy wire acceptance (CI or authorized staging only)

The existing topology probe, mounted Rack matrix, and stand-in curl checks do
**not** establish proxy sanitization, raw duplicate-header handling, or origin
isolation. `proxy-wire.py` is a separate, opt-in wire check extending this tooling
without changing the topology matrix's direct-to-app expectations. Use a disposable
CI runner or an authorized test checkout; local tests require the `.test-mode`
sentinel under [repository test guidance](../../AGENTS.md#running-tests).

### Disposable real-Caddy fixture

Prerequisites: Python 3.9+ and an already-installed Caddy binary. Provision and pin
the Caddy version in the CI job using the deployment's approved version; this
script does not download dependencies. In a disposable CI runner:

```bash
python3 tools/host-seam/proxy-wire.py fixture --caddy caddy
```

This starts only loopback listeners: a real Caddy process using
`proxy-wire.caddy` and a Python upstream header capture. It sends actual raw
HTTP/1.1 requests and inspects the fields received **after Caddy**, preserving
separate physical duplicate field lines. No app, datastore, tenant seed, TLS
certificate, or deployed infrastructure is required. It stops only its own
process and listeners when finished.

Proposed acceptance criteria (not a claim about deployed configuration):

- Exactly one upstream `Host: origin-target.internal` and exactly one
  `X-Forwarded-Host` naming the public request host.
- No upstream `Apx-Incoming-Host`, `X-Original-Host`, or `Forwarded`.
- A poisoned single header, both duplicate orders, comma-joined values, and
  simultaneous carrier poisoning leave the upstream identity unchanged.
- Two physical `Host` fields in either order receive HTTP 400 or 421. A reset,
  timeout, or missing response is inconclusive, not a passing rejection.

The config reuses the rewrite/removal operations from
`caddy-approximated-lane.caddy`, but deliberately removes its developer TLS paths
and static-file routing. This checks the supplied Caddy config, **not**
Approximated, the deployed edge config, the application HTTP server's parser, or
SSO. Do not substitute its success for those checks.

Each result is JSONL with a stable finding ID and case name. Exit codes: `0`
means all assertions passed for that run and vantage; `1` means an assertion
failed; `2` means setup or transport was inconclusive. A failing clean control
stops the matrix rather than mislabelling setup as header poisoning.

### CI fixture gate

Read workflow coverage:

- `.github/workflows/ci.yml` includes `tools/host-seam/**` in its Ruby change
  filter, but the mounted matrix is application-level evidence only.
- `.github/workflows/static-analysis.yml` runs the shell suite without services
  or network; it does not execute this Python wire check.
- `.github/workflows/compose-smoke.yml`, `full-stack-smoke`, already builds
  Caddy, starts the app, and checks `GET /api/v2/status` through HTTPS. Its PR
  paths do not include `tools/host-seam/**`. Its ingress status check does not
  assert header overwrite or raw duplicates.

The `host-proxy-wire` job in `.github/workflows/ci.yml` runs the fixture with
Caddy 2.11.4, matching the version in `docker/variants/caddy.dockerfile`. It
triggers on the Ruby change filter, including `tools/host-seam/**`, and retains
JSONL results, the resolved image digest, and the binary version as artifacts.
The CI result has not been inspected; adding the job is not evidence that it passed.
The local Caddy 2.11.4 fixture passed 20 cases on 2026-10-03. See the
[five-item follow-up validation record](follow-up-validation.md) for exact commands,
application-test totals, unresolved findings, and execution limits.

The staging command below still requires a registered custom domain and domains
enabled in the actual deployment. The compose smoke job's current localhost
status check is not a custom-domain oracle.

### Deployment acceptance checklist

Run only in authorized CI/staging. Get values from the deployment inventory; no
staging hostname, origin address, or origin port is supplied by this repository.
The following commands intentionally require operator-supplied values rather
than invented endpoints. From repo root, in Bash:

```bash
: "${HOST_SEAM_PUBLIC_URL:?Set the actual tenant dynamic URL from staging inventory}"
python3 tools/host-seam/proxy-wire.py staging \
  --url "$HOST_SEAM_PUBLIC_URL" --strategy custom
```

Use the existing dynamic `/` route documented by `topology-probe.sh`, on an
already-registered custom domain with `DOMAINS_ENABLED=true`. The clean control
must emit exactly one `O-Display-Domain` matching the URL hostname and
`O-Domain-Strategy: custom`. GET only; no SSO POST, cookies, redirects followed,
seeding, or IdP requests. HTTPS verifies certificates. For a private staging CA,
add `--ca-file` with the approved CA bundle. To test an inventoried ingress IP
without changing SNI or Host, add `--connect-address` with that IP.

- [ ] Record the edge/provider versions, deployed config revision, runner source
      IP/network, public URL, and results. Run through the actual provider-to-edge
      chain, not only an internal load balancer shortcut.
- [ ] Repeat the staging command for each ingress route and canonical surface
      (use `--strategy canonical` for the latter). Inspect failures; a static page,
      WAF block, or missing O-\* oracle is not proof of overwrite.
- [ ] Observe the origin-side headers using authorized edge/origin logging or
      a temporary capture backend in a disposable deployment. Staging O-\* results
      show effective app identity only: ignored poison could remain on the wire.
      Do not install this unauthenticated capture server on a public production
      listener. Never log cookies, authorization headers, or tenant credentials.
- [ ] Inventory every origin listener/address, including IPv4, IPv6, public
      load-balancer listeners, and alternate ports. From an **untrusted external
      vantage**, run once per inventoried address/port:

```bash
: "${HOST_SEAM_ORIGIN_ADDRESS:?Set an actual origin address from staging inventory}"
: "${HOST_SEAM_ORIGIN_PORT:?Set its actual listener port from staging inventory}"
python3 tools/host-seam/proxy-wire.py origin \
  --address "$HOST_SEAM_ORIGIN_ADDRESS" --port "$HOST_SEAM_ORIGIN_PORT"
```

This makes one TCP connection attempt and sends no HTTP. TCP success fails the
proposed strict network-isolation criterion, even if HTTP might later reject
the caller. Connection refusal passes only that address/port/vantage at that
time; it does not prove firewall policy. DNS failure, timeout, and routing
errors exit `2`. For silently dropped traffic, corroborate with enforced
firewall/security-group rules and counters; do not relabel a timeout a pass.
Use literal inventoried IPs to avoid checking only one DNS answer.

- [ ] Correlate external failures with origin health and a successful authorized
      ingress control. Review firewall/ACL rules permitting only the approved proxy
      sources, and app trusted-proxy configuration. A dead listener is not evidence
      of correct isolation. If the origin intentionally accepts TCP and gates at
      mTLS or HTTP instead, this strict TCP check is insufficient: document and
      verify that boundary separately, including forged carriers from an untrusted
      source. No authenticated-origin boundary is validated by this script.

### Remaining limitations ledger

| ID             | Status and evidence still required                                                                                                                                                                                                                                |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HS-PROXY-001` | Local Caddy 2.11.4 fixture passed; staging not run. The fixture demonstrates only the supplied Caddy policy. Actual provider/edge overwrite and upstream removal require deployed-path results and origin-side capture/config evidence.                           |
| `HS-PROXY-002` | Raw HTTP/1.1 duplicate carrier and Host cases passed locally; duplicate Host returned 400 in both orders. Fixture ends at a Python capture backend; actual app-server parsing requires staging results. HTTP/2 and HTTP/3 duplicates/translation are not covered. |
| `HS-PROXY-003` | Explicit-address TCP reachability command added, not executed. Complete origin inventory, untrusted vantage, healthy-origin control, and enforced network or authenticated-origin policy evidence remain unavailable.                                             |
| `HS-PROXY-004` | Fixture wired into the CI `host-proxy-wire` job; CI results not inspected. Local fixture execution passed, but does not establish CI success. This gate covers the disposable Caddy fixture only, not deployed infrastructure.                                    |

## When to run

1. You changed host/domain logic and need a fast gate: run `bin/host-seam probe`.
2. Probe shows non-`ok`: verify setup (`ORGS_SSO_ENABLED=true`,
   `TRUSTED_PROXY_ENABLED=true`, seeded custom domain **with an enabled
   SsoConfig** — `FIXTURE_MISSING` means the SsoConfig half is absent).
3. You need "which release introduced this": run `bin/host-seam sweep` on target
   tags.
4. Sweep has `IMAGE_UNAVAILABLE` / `START_FAILED` / `NEVER_READY`: do not trust
   transition conclusions yet.
5. You need browser-path parity with rewritten ingress: enable
   `caddy-approximated-lane.caddy` and compare preserved vs rewritten lanes.
