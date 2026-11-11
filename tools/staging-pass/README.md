# Staging pass

A production-shaped install of the working tree, driven over HTTP, next to
the published image of an earlier release. It covers what the test lanes do
not: full authentication mode end to end, the proxy configuration the full
compose stack ships, the job system as separate processes, and two versions
taking turns on the same data.

It is not a lane. It boots the application in `RACK_ENV=production` against
its own throwaway services on their own ports (below), never the lane
services on 21xx or anything on canonical ports. Do not point it at an
install that has data.

Records of runs: [2026-11-11, v0.26.20 candidate](2026-11-11-secret-path-validation.md).

## What runs

| Piece | How | Stands in for |
| --- | --- | --- |
| Working tree | `git archive HEAD` into `$STAGING_ROOT/head`, built assets and `etc/` defaults copied as the Dockerfile's final stage does, run as uid 1001 with `bundle exec puma -C etc/puma.rb`, `bin/ots worker`, `bin/ots scheduler` | the `app`, `worker-email` and `scheduler` services of `docker/compose/docker-compose.full.yml` |
| Earlier release | the published image, `--network host`, the same env file and data directory | the release being upgraded from or rolled back to |
| Proxy | Caddy built by xcaddy at the commit and plugin set `docker/variants/caddy.dockerfile` pins, running `etc/examples/Caddyfile-example` unmodified, empty `PUBLIC_DIR` | the `proxy` service |
| Valkey, RabbitMQ | the images and server flags the full compose pins (`--requirepass`, `--timeout 30`, AOF) | `maindb`, `rabbitmq` |
| PostgreSQL | the test compose's pin, initialised with `initialize_auth_db.sql` | a Postgres auth database (SQLite is the compose default and is tested too) |
| Mailpit | the mailpit compose pin | an SMTP server |

Two things differ from the compose stack and are worth knowing when reading
results:

- The working tree runs natively, not from an image built by the
  Dockerfile. The image build itself is not exercised here.
- The Caddyfile forces the ACME issuer, which cannot issue for a test name.
  `prepare.sh` places a certificate signed by a throwaway CA where the ACME
  issuer would have stored it, so the Caddyfile stays byte-identical.

Clients connect from RFC 5737 documentation addresses added to loopback.
The Caddyfile trusts private ranges, so a client on 127.0.0.1 would be
treated as a trusted proxy; these addresses make each client a distinct
public peer.

| Service | Address |
| --- | --- |
| Proxy | `https://secrets.staging.test` (203.0.113.1:443, :80) |
| Puma | 127.0.0.1:3000 |
| Valkey | 127.0.0.1:6479 |
| RabbitMQ | 127.0.0.1:5772, management 127.0.0.1:15772 |
| PostgreSQL | 127.0.0.1:5532 |
| Mailpit | SMTP 127.0.0.1:1125, API 127.0.0.1:8125 |

## Running it

```bash
tools/staging-pass/prepare.sh                 # once; root, docker, Go, Ruby, pnpm
(setsid tools/staging-pass/run-caddy.sh > /srv/ots-staging/logs/caddy.log 2>&1 &)
tools/staging-pass/stack.sh up head           # web, worker, scheduler
cd tools/staging-pass/tests
python3 suite_core.py r1 head-sqlite          # full-mode secret path
python3 suite_proxy.py r1 head-sqlite         # the proxy (needs suite_core's fixtures)
python3 suite_jobs.py r1 head-sqlite head     # queue, worker, scheduler, expiry (about 9 minutes)
python3 suite_faults.py r1 head-sqlite        # SIGKILL, datastore and upstream outages
node browser_e2e.js <email> <password> head-sqlite
cd .. && ./xdir-run.sh sqlite && ./xdir-run.sh pg   # two directions against the earlier release
```

`STAGING_ROOT` (default `/srv/ots-staging`) contains the install, env files and
logs; `STAGING_STATE` (default `$STAGING_ROOT/state`) the generated secrets,
the CA and the result ledgers (`results/<suite>.jsonl`, one JSON object per
check with its ID, verdict and what was observed). `BASELINE_IMAGE` names the
earlier release.

The first argument of each suite is a run id that makes its account names
unique, so a suite can be re-run on the same data. `suite_core.py` can also
be pointed at the earlier release (`stack.sh up v19`, label `v19-sqlite`):
the checks that fail there and pass on the working tree are the behaviour
the release changed.

## Reading results

- The polite client retries a 429 after its `Retry-After`. With the shipped
  Caddyfile all clients share one rate-limit bucket (see the 2026-11-11
  record), so suites pause for it; race tests switch the retry off and space
  their rounds.
- `browser_e2e.js` cannot pass against the shipped Caddyfile for the reasons
  in the same record. `Caddyfile-candidate.patch` is the configuration it
  was run with; it is a proposal, not applied to `etc/examples`.
- A red check is a finding only after it is traced: the first runs of these
  suites had assertion errors of their own, corrected before the recorded
  runs.

## Files

| File | Purpose |
| --- | --- |
| `prepare.sh` | one-time setup: user, secrets, install tree, proxy build, certificate, addresses, services |
| `services.sh` | backing service containers |
| `stack.sh` | start/stop a version's web, worker, scheduler; reset the datastores |
| `run-head.sh`, `run-caddy.sh` | one process of the working tree's install; the proxy |
| `patch_jobs_config.py` | switch on the scheduled jobs that ship off, with short schedules |
| `xdir-run.sh` | the two-direction sequence |
| `tests/stg.py`, `tests/audit.py` | client helpers and ledger; datastore audit of secret/receipt pairs |
| `tests/suite_*.py`, `tests/xdir_*.py`, `tests/browser_e2e.js` | the checks |
