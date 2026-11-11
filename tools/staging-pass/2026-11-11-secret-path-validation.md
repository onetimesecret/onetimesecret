# Staging pass: core secret path in full mode, behind the proxy, with jobs

Execution record, 2026-11-11. Tested revision: `main` at
`66bfd90600026f7d276a40cf86f175fd9bc3573a` (v0.26.20 not yet tagged; otto
2.12.0, familia 2.13.0 per `Gemfile.lock`). Earlier release: the published
image `onetimesecret/onetimesecret:v0.26.19`
(`sha256:eb630051046042195a1dee73367f4f02a33ab3275bdc4d77a5d2c3dba88d3f0e`,
commit `e98a88c`, otto 2.11.0, familia 2.12.0).

This record reports results observed on one local machine. It is not hosted
CI, not a release approval, and not a statement about any live deployment.
The harness and how the environment differs from the compose stack are in
[README.md](README.md).

## Why

The 2026-11-10 two-direction test ran in simple mode against a bare Valkey.
Three areas were untested: full authentication mode, the proxy the full
compose stack ships, and the job system. This pass covers them for the
changes to the secret path since v0.26.19: creation in one transaction,
conditional receipt updates, request-input validation ahead of dispatch.

## Results

All requests went client → Caddy (TLS 1.3) → Puma unless noted.

| Suite | Auth DB | Passed | Failed | What the failures are |
| --- | --- | --- | --- | --- |
| Core path on `main` (`suite_core`) | SQLite | 53 | 1 | API-1 |
| Core path on `main` | PostgreSQL | 53 | 1 | API-1 |
| Core path on v0.26.19 (baseline) | SQLite | 41 | 13 | the behaviour this release changed, plus API-1 (table below) |
| Proxy, shipped Caddyfile (`suite_proxy`) | n/a | 25 | 2 | PX-1 |
| Job system on `main` (`suite_jobs`) | PostgreSQL | 26 | 0 | |
| Job system on `main` | SQLite | 23 | 3 | assertion errors of mine (set-member encoding, a grep pattern); those three checks re-run on their own: 3 of 3 |
| Faults on `main` (`suite_faults`) | SQLite | 10 | 1 | PX-4 |
| Browser journey, shipped Caddyfile | SQLite | 0 | 1 | the app never loads: PX-2, PX-3 |
| Browser journey, candidate Caddyfile | SQLite | 10 | 0 | |
| v0.26.19 writes → `main` reads | SQLite | 24 + 38 | 0 | |
| `main` writes → v0.26.19 reads | SQLite | 24 + 37 | 1 | v0.26.19's own memo-edit behaviour (R30, below) |
| v0.26.19 writes → `main` reads | PostgreSQL | 24 + 38 | 0 | |
| `main` writes → v0.26.19 reads | PostgreSQL | 24 + 37 | 1 | R30 again |

Unhandled errors in the application logs: on `main`, only the API-1
`TypeError`s and two `Redis::CannotConnectError`s during the injected
datastore outage. In the four two-direction runs, none on either version.

### Full mode

Sign-up, the verification email (queue → worker → SMTP), login, session
with CSRF, API token, then v1, v2 (Basic auth), v3 (session) and guest
routes: conceal, generate, show, reveal, burn, memo, lists by owner and by
organization. Each pair was checked in Valkey: both hashes, TTLs (secret
`ttl`, receipt `2 × ttl`), owner and organization index entries, both
`instances` sets.

- 12 concurrent reveals × 6: one caller gets the value each time.
- Burn racing reveal × 20: one winner each time, the receipt state matches
  it, the secret is gone.
- Memo edits racing reveal × 15: the receipt ends `revealed`, the TTL is not
  extended.
- After expiry: memo edit, burn, show and reveal answer 404 and recreate no
  key.
- 20 `SIGKILL`s on Puma workers during a burst straight at Puma: 2,846
  creations answered 200, each with its full pair; 76 connections dropped;
  the audit of 2,932 secrets and 3,044 receipts found no secret without its
  receipt, no partial hash and no key without a TTL.
- Datastore stopped: creation and reveal answer 500 after about 8 seconds
  each, with no `Retry-After`; nothing leaks connection details in the body.
  The app recovers without a restart and a secret from before the outage
  reveals once.
- Valkey's `--timeout 30` (from the full compose): requests after 45 seconds
  idle succeed.

### What this release changed, seen from both versions

The same suite against the v0.26.19 image and against `main`:

| Check | v0.26.19 | `main` |
| --- | --- | --- |
| `HEAD` on the one-time read routes | 200; consumes the creator's one-time display of a generated value | 405 with `Allow`; nothing consumed |
| JSON body naming another identifier on reveal, burn, memo | acts on the body's identifier: a reveal of A returned B's value | acts on the path |
| `OPTIONS /secret/conceal` | 422/200 and one secret created | 204, nothing created |
| Memo edit | receipt TTL reset to 14 days | TTL unchanged |
| Memo edit racing a reveal | receipt back in `new` after the reveal in some rounds | always `revealed` |
| Nested `scope` parameter, type-conflicting query | 500 | 422, 400 |
| Unparseable JSON or form body | 400, empty body | 400 with a JSON message |

### Proxy

TLS 1.3 only, HTTP/2, plain HTTP redirected. No duplicated security or
cache header between app and proxy. One `X-Request-ID` per response, equal
to `O-Request-ID`, replacing a client-supplied one, and the same id in the
app's error body and log. The app resolves the proxied client address, a
forged `X-Forwarded-For`, `X-Forwarded-Host`, `-Proto` or `-Port` from a
public client changes nothing, and the anonymous-creation limiter keys on
the client's masked network. Chunked bodies, `Expect: 100-continue`, gzip
responses, unicode and sizes up to the app's limit round-trip. Secret
values, passphrases, API tokens and verification keys appear in no proxy or
app log; the proxy log has no query strings.

### Job system

Recipient email through `email.message.send`; three emails wait on the
queue while the worker is stopped and are delivered once each after it
starts; a republished copy with the same `message_id` is dropped; with the
broker stopped creation still answers 200 and the email goes out through
the fallback; publisher and worker recover when the broker returns; a
worker stopped mid-stream loses none of 12. The scheduler warns about a
long-lived secret once. With `auto_repair` on, phantom cleanup removes the
index entries of expired pairs and leaves live pairs alone;
`InstancesRebuildJob` reports nothing missing.

### Two directions, full mode

One version writes an account, a logged-in session, an API token and
secrets in every state (new, previewed, passphrase, generated, revealed,
burned, with memo, with recipient, v1, guest, 7-day), and leaves one email
on the queue. The other version then: accepts the session cookie and the
token, lists the same receipts with the same states, reveals every value
intact, shows the generated value once, edits memos, burns, delivers the
queued email and sends the expiration warning. Response field sets for v2
list/show/conceal and v3 conceal are identical between versions.

R30: after `main` wrote and v0.26.19 took over, a memo edit on v0.26.19
reset the receipt TTL to 14 days. v0.26.19 does the same to receipts it
created itself (baseline row above). A rollback brings that behaviour back;
it is not caused by data `main` wrote.

## Findings ledger

| ID | Finding | In v0.26.19 too | Disposition |
| --- | --- | --- | --- |
| PX-1 | The Caddyfile's five rate-limit zones use `key {remote_ip}`. That is not a Caddyfile placeholder: `caddy adapt` leaves the literal string, and at run time every client shares one bucket per zone. A second address was answered 429 (`Retry-After: 60`) after another address's five login attempts, and 429 during another address's burst. | yes | Open. Needs an operator decision: the fix changes throttling. |
| PX-2 | `handle @dist { file_server }` answers 404 for `/dist/*` files that are not under `PUBLIC_DIR`. The proxy image ships that directory empty and the full compose mounts nothing into it, so every built asset is 404 through the proxy (200 straight from Puma). | yes | Open. |
| PX-3 | The `general` zone (20 per second) has no matcher, so it counts static assets. One load of `/signin` made 60 requests: 20 answered, 40 throttled, and the app never became ready. This happens with one browser and would with per-client keys too. | yes | Open. Needs an operator decision. |
| PX-4 | Responses the proxy generates itself (429, 502) carry `Server: Caddy` and none of the header block (`Cache-Control`, `X-Content-Type-Options`, …). | yes | Open, low. |
| API-1 | A JSON body that parses but is not an object (`[1]`, `"s"`, `7`, `true`) is answered 500 on v1 and v2 routes (`TypeError` in `Rack::Request#params`, called from Otto's route handler); v3 answers 422. Not traced further. | yes (v2) | Open. Not a regression. |
| API-2 | Object values where strings are expected are accepted: a `memo` of `{"a":1}` is stored as `{"a" => 1}`; `passphrase` and `secret` likewise. | yes | Observation. |
| LOG-1 | The app's `[Otto] Auth strategy result` line and the proxy access log print request paths with full secret and receipt identifiers; the app's request log redacts them. | the same app log line exists there | Observation. |
| JOB-1 | `HousekeepingJob` reports `reserialize_fields` `modified: 7` for the same 7 customers on every run. | not checked | Not investigated; outside the secret path. |

On PX-2 and PX-3, the documented full stack as shipped serves the API but
not the web UI. Hosted CI's ingress check requests `/api/v2/status` only
(`compose-smoke.yml`), so it does not see either.

On PX-2, `docker/variants/caddy.dockerfile` says of the empty directory:
`so an empty dir means "proxy everything"`. On PX-1, the Caddyfile's own
comment reads `5r/m => 300 requests/hour per IP`.

On API-1, `CHANGELOG.rst` for 0.26.20 says: "Malformed request input is
answered as a client error instead of a server error." The plan records the
non-object-JSON review finding on #4871 as refuted. A lookup delegated
during this pass read the PR comment
(`pull/4871#issuecomment-6665390799`) as reproducing
`POST /api/v3/guest/secret/conceal` only; v3 does answer 422 here. The v1
and v2 result above is outside what that comment tested.

### Candidate proxy change (not applied)

[`Caddyfile-candidate.patch`](Caddyfile-candidate.patch) keys the zones on
`{client_ip}`, takes static assets out of the `general` zone, and adds a
`file` test to `@dist` so a missing file falls through to the app. With it:
the page loads with an empty `PUBLIC_DIR` (74 responses, all 200), the
browser journey passes 10 of 10, the sixth login attempt from one address
is still throttled and another address is not. It was run for those checks
only. It relaxes a throttle, so it is left for the operator to decide.

## Not tested

- The image built by the Dockerfile. This session's network policy blocks
  `deb.debian.org`, so `main` ran natively (Ubuntu 24.04, Ruby 3.4.10; the
  frontend built with Node 22, not 26). v0.26.19 ran from its image.
- `docker compose` itself: healthchecks, volumes, service ordering.
- Real ACME issuance, HTTP/3, a CDN or Approximated in front of Caddy.
- Custom domains, so the domain index registration inside the creation
  transaction; SSO; MFA; billing limits; PASETO tokens (off by default);
  the incoming API beyond one malformed body (off by default).
- A command rejected inside the creation `EXEC`. Process death and outage
  were injected; a partial `EXEC` was not.
- Shipped job schedules. Scheduled jobs ran every 1 to 2 minutes with
  `auto_repair` on, through `patch_jobs_config.py`.
- Duration. The longest continuous run was about an hour.
- Concurrency above 20 requests per second through the proxy (PX-1). The
  `SIGKILL` burst went straight to Puma.
- The fault suite on PostgreSQL; it concerns Valkey and the proxy.
- Hosted CI and the test lanes: no application code changed in this pass.
