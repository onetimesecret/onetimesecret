# Test Lanes

One lane = one process boundary = one CI job (or matrix row). Each lane
directory holds the lane's environment (`env`), what it runs (`tasks`),
and a direnv hook (`.envrc`) for interactive work. `base.env` holds the
lane-invariant environment; `overlays/` holds env-only toggles.

This tree — together with `compose.test.yml` at the repo root — is the
single source of truth for "what do tests need". CI and local development
both enter through `tests/lanes/run`, which is what makes the two
environments the same environment.

## Quick start

```console
$ docker compose -f compose.test.yml up --wait -d   # or: podman compose
$ tests/lanes/run --list
$ tests/lanes/run unit
$ tests/lanes/run full-pg --overlay billing
$ docker compose -f compose.test.yml down
```

### Iterating on one file: `--only`

A whole lane is minutes; one file is seconds. `--only <path>` runs just
that file (repeatable) in the lane's environment, skipping the lane's
tasks file:

```console
$ tests/lanes/run simple --only apps/api/domains/spec/integration/simple/domain_sso_config_spec.rb
$ tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb:145
$ tests/lanes/run unit --only try/logic/sso_config/ssrf_protection_transition_try.rb
```

- Pick the lane whose env the file expects — a `spec/integration/full/`
  file under `simple` fails on missing auth-mode config, not on its own
  logic. The lane table below maps lane to what it runs.
- Runner is chosen by filename: `*_try.rb` goes to `try --agent`,
  everything else to `rspec`. One kind per invocation.
- `path:LINE` is forwarded to rspec, so a single example works.
- The hermetic boundary is unchanged: same scrub, same lane env, same
  exec. This is the sanctioned fast loop, not a bypass.
- What it skips is the rest of the tasks file — including setup steps
  like `pnpm run locales:sync` in the full lanes. Iterate with `--only`,
  then run the whole lane before pushing. CI runs lanes, not files.

Prerequisites: `bash` 5+ (the runner's env scrub needs it; stock macOS
ships 3.2 — `brew install bash`), `bundle install`, `pnpm install`,
`python3` (locale compilation). Lanes whose specs read built frontend
assets (`unit`, `smoke`) need `public/web/dist/` populated — `pnpm run
build` locally; CI provides it as a build artifact.

## Lanes

| Lane                | Services                   | Runs                                                        | CI job                                   |
| ------------------- | -------------------------- | ----------------------------------------------------------- | ---------------------------------------- |
| `unit`              | valkey, rabbitmq           | `try:unit`, `spec:fast`                                     | ruby-unit (T2)                           |
| `simple`            | valkey, rabbitmq           | `try:integration:simple`, `spec:integration:simple`         | ruby-integration-simple (T3)             |
| `full-sqlite`       | valkey, rabbitmq           | `spec:integration:full`                                     | ruby-integration-full — SQLite rows      |
| `full-pg`           | valkey, rabbitmq, postgres | `spec:integration:full:postgres`                            | ruby-integration-full — PG rows          |
| `full-pg-agnostic`  | valkey, rabbitmq, postgres | `spec:integration:full:agnostic_on_pg`                      | ruby-integration-full — PG agnostic rows |
| `disabled`          | valkey, rabbitmq           | `spec:integration:disabled`                                 | ruby-integration-disabled (T3)           |
| `api`               | valkey, rabbitmq           | `spec:api`                                                  | blocking step, T3 simple job             |
| `smoke`             | valkey, rabbitmq           | `pnpm test:smoke`                                           | smoke-test (T3)                          |
| `migrations-sqlite` | valkey, rabbitmq           | `spec:integration:migrations:sqlite`                        | migration-tests.yml — SQLite job         |
| `migrations-pg`     | valkey, rabbitmq, postgres | `spec:integration:migrations:postgres` + dual-URL check     | migration-tests.yml — PostgreSQL job     |
| `selftest`          | none                       | prints its own environment (boundary fixture)               | none — driven by `spec/unit/lanes/`      |

`api` and `smoke` don't exercise the job queue, but `base.env` carries
`RABBITMQ_URL` for every lane and the runner's preflight requires every
`127.0.0.1:21xx` endpoint *present* in a lane's env to be reachable — so
rabbitmq must be up. `selftest` is the one exception: its own `env`
blanks all three URLs, which leaves the preflight with nothing to check.

The billing matrix rows are the full-mode lanes with `--overlay billing`.
Billing requires `AUTHENTICATION_MODE=full`; `run` rejects the overlay on
any other lane.

Directories exist for dimensions that change **which specs run** (auth
mode, database engine — mirroring `spec/integration/{simple,full,disabled}`).
Overlays exist for dimensions that only change **environment**
(billing on/off). Adding a full directory per combination would double
the tree per toggle; don't.

Vitest, lint, and type-check need no services or special env, so they
have no lanes — run them via pnpm directly.

## Ports: the 21 rule

Every test service publishes on `127.0.0.1` with a port starting with 21. New services take "21 + last two digits of the canonical port";
valkey predates the scheme and keeps its established 2163. Dev services
keep canonical ports. A leaked dev config therefore cannot reach a test
service, and a test run cannot reach dev data. This plus the hermetic
runner is the answer to "tests wiped my dev database".

| Service  | Test port | Canonical                 |
| -------- | --------- | ------------------------- |
| valkey   | 2163      | 6379 (port grandfathered) |
| postgres | 2154      | 5432                      |
| rabbitmq | 2156      | 5672                      |

Port mappings are defined **only** in `compose.test.yml`. The env files
here carry matching URLs; if a URL in this tree doesn't point at a 21xx
port, that's a bug.

## Per-worktree datastore isolation

All checkouts (worktrees included) share the one test valkey on 2163,
and two lane runs sharing DB 0 contaminate each other's fixtures — the
failure set then shifts run to run with sibling activity (#4168). So the
runner assigns each worktree its own valkey DB index, derived
deterministically from the repo root path (range 1..1023;
`compose.test.yml` starts valkey with `--databases 1024`). The index is
exported as `LANES_DATASTORE_DB`; `spec/config.test.yaml` interpolates
it into `redis.uri`, and the runner rewrites `REDIS_URL`/`VALKEY_URL` to
match. Host and port never vary — this selects a database *on* the test
service, it cannot redirect a run to another service.

DB 0 is reserved: it's what CI containers and interactive
`bundle exec rspec` (no `LANES_DATASTORE_DB` set) use. A lane env file
or overlay may pin an index explicitly by setting `LANES_DATASTORE_DB`;
the calling shell cannot (the scrub clears it like everything else).
The runner probes `SELECT <index>` before starting and tells you to
recreate the valkey container if it still has the 16-database default.

PostgreSQL (2154) has **no** per-worktree isolation yet: the full/
migrations lanes still share `onetime_auth_test`. Avoid running two
PG lanes concurrently across worktrees.

## Hermetic runs vs. interactive shells

`tests/lanes/run` clears every variable the calling shell exports,
except a six-name keep-list, before loading `base.env` -> `<lane>/env`
-> overlays. Allowlist, not denylist: a denylist can never enumerate
every var that might leak (this repo has been bitten three times —
`PG*`, `NODE_ENV`, then `CUSTOM_MAIL_*`/`INCOMING_*`/`ORGS_*`/`BRAND_*`
in one incident), so the boundary now clears everything and lets only
named exceptions through. A test run behaves identically whether
launched from a dev shell, a lane directory, or CI.

That scrub needs bash 5 — `mapfile`, plus empty-array expansion under
`set -u` — so the runner checks `BASH_VERSINFO` before anything else and
refuses to start on an older shell. The floor is pinned in
`.bash-version` at the repo root (next to `.ruby-version` and
`.node-version`); the runner, `bin/setup --doctor`, and the
hermetic-boundary spec all read it from there rather than each carrying
their own copy of the number. Stock macOS is bash 3.2 and
`#!/usr/bin/env bash` finds it, so without the check a Mac contributor
gets `mapfile: command not found` from inside the boundary block rather
than a sentence telling them what to install. The fix is `brew install
bash`. The floor stops at this file: `bin/setup` stays 3.2-compatible on
purpose, because it has to run on a Mac before Homebrew bash exists.

Exported shell functions (`export -f`) are cleared the same way — bash
re-materializes those in the exec'd task process regardless of any
variable scrub, so a dev-shell function shadowing `git`, `bundle`,
`docker`, `podman`, or `rake` (via `.bashrc`, direnv, an asdf shim, or a
compromised profile) would otherwise run silently inside every lane.

The scrub is the first thing `run` does after `set -euo pipefail`, and it
has to stay there. Assigning into a name the caller already exported keeps
the export attribute, so a variable the script sets above the scrub would
be listed and cleared as if it were ambient — then read back as unbound.
That is not hypothetical: `run-test-lane/action.yml` passes the lane name
as step env `LANE`, and `LANE="$1"` above the scrub took every CI job down
with `LANE: unbound variable`. Add new script variables below the block,
never above it.

The keep-list is exactly:

```
PATH HOME CI LANES_NO_AUTOSTART RSPEC_OUTPUT_FILE COVERAGE
```

`PATH`/`HOME` resolve the toolchain (rbenv/ruby, pnpm/node, python3,
docker/podman); `CI` is read directly by billing VCR setup and a timing
spec to select CI-safe behavior; `LANES_NO_AUTOSTART`/`RSPEC_OUTPUT_FILE`/
`COVERAGE` are CI-plumbing signals set at step level, indistinguishable
from a leaked dev-shell var unless named explicitly. That's the whole
list — see the scrub block in `tests/lanes/run` for the one-line
justification of each.

The container-daemon variables — `DOCKER_HOST`, `DOCKER_CONTEXT`,
`DOCKER_CONFIG`, `DOCKER_CERT_PATH`, `DOCKER_TLS_VERIFY`,
`DOCKER_API_VERSION`, `CONTAINER_HOST`, `CONTAINER_CONNECTION`,
`CONTAINER_SSHKEY`, `CONTAINERS_CONF`, `XDG_RUNTIME_DIR` — are **not** on
that list and never reach the test process. The runner snapshots them into shell variables before the scrub
and hands them to the `docker compose` / `podman compose` autostart
invocation alone. Without the snapshot, a contributor whose daemon is
colima, OrbStack, or rootless podman would have autostart talk to the
default socket — the wrong daemon, or none — while their services sat
untouched on the real one. Passing them through to the tests instead
would be the leak the scrub exists to stop, so they go to the compose
client and stop there.

**A test needs an env var that isn't reaching it? Add it to `base.env`**
(if every lane needs it) **or the lane's own `env` file** (if only that
lane does). Do not add it to the keep-list in `tests/lanes/run` — that
list is for CI-plumbing and toolchain-resolution singletons only, and
its existing at all is a deliberate, reviewed exception each time.

To see exactly what got cleared: `LANES_DEBUG_ENV=1 tests/lanes/run
<lane>` prints every scrubbed variable to stderr as
`[lane:scrub] unset NAME` and every scrubbed exported function as
`[lane:scrub] unset -f NAME`. If the var you expected is in that list,
the scrub is working correctly — it needs to move into `base.env` or the
lane's `env` file, not be exempted from the scrub.

Determinism pins are set on purpose rather than left to platform
defaults, for the same reason the boundary is an allowlist: leaving them
ambient means test determinism depends on whichever machine happens to
run the suite. Which file a pin lives in decides who else it affects.
`NODE_ENV=test` and `TZ=UTC` are in `base.env`, which the lane `.envrc`
hooks below also dotenv-load — so they rewrite an interactive lane shell,
and that is the intent: a lane shell should behave like a lane run.
`NODE_ENV` is read directly by application code (`src/utils/debug.ts`,
`src/utils/schemaValidation.ts`); `TZ` is read by the language runtimes,
so it moves every timestamp-adjacent assertion. Both change observable
behavior, which is what puts them on the parity side. `LANG`/`LC_ALL` are
pinned in `tests/lanes/run` instead, after the scrub and before
`base.env` loads. A fixed locale is a runner concern, not environment
parity; pinning it in `base.env` would quietly change the locale of
every shell that `cd`s into a lane directory, which is a side effect
nobody asked for.

For interactive work, `cd` into a lane and `direnv allow` (once): your
shell — and your atuin history — carries that lane's environment, the
same directory-per-environment idiom as the infra config system. The
lane `.envrc` files deliberately do **not** `source_up` past
`tests/lanes/`, so the dev environment never bleeds in. Optional
overlays for a shell session: `echo billing > .overlays` (gitignored).

## Rules

1. Endpoints in this tree point only at `127.0.0.1` 21xx ports.
2. No real secrets. `base.env` values are public dummies, committed on
   purpose (deterministic across contributors and CI). Real environment
   configuration lives outside this repository, as always.
3. A lane's `tasks` file owns its generated prerequisites (locales,
   JSON schemas) so "works in CI, fails locally" can't come from a
   missing pre-step.
4. Gating policy (blocking vs. advisory, parallelism, artifacts,
   reporting) belongs to CI. Lanes define _what runs in which
   environment_; the workflow decides what it means when a lane fails.

## CI adoption status

Every workflow that runs Ruby test suites enters through this tree; each
job starts services with `docker compose -f compose.test.yml up --wait`
and executes `tests/lanes/run <lane>`:

- `.github/workflows/ci.yml` — all Ruby test jobs, via the
  `run-test-lane` composite action (which layers on the CI-only
  concerns: failure-tail PR comments, job summaries, and the
  `LANES_NO_AUTOSTART`/`RSPEC_OUTPUT_FILE` step env). `COVERAGE` is not
  the composite's: `ci.yml` writes it to `GITHUB_ENV` itself, and it
  survives the scrub only because it is keep-listed. The full-mode
  matrix rows are lane names + overlays.
- `.github/workflows/migration-tests.yml` — the SQLite and PostgreSQL
  jobs run the `migrations-*` lanes via the same composite. The
  concurrent-boot job is deliberately not a lane (it choreographs
  parallel boot processes, which is CI-side orchestration, rule 4) but
  still takes services from `compose.test.yml`.
- `.github/workflows/ruby-4-preview.yml` — runs lanes directly (no
  composite): the workflow is advisory-only, so failure-tail comments
  and results plumbing would be noise.
- `.github/workflows/fresh-clone.yml` — the contributor-path job runs
  `tests/lanes/run unit` directly: it proves the commands CONTRIBUTING.md
  documents, and `bin/setup --test` has already started the compose
  services by the time the lane's preflight runs.

Every job above pins `runs-on: ubuntu-24.04`, which ships bash 5.2, so
the runner's bash 5 floor is satisfied with no setup step. The CI
environment still on bash 3.2 is `installer.yml`'s macOS job, and it
never enters a lane — see the exceptions below. That is what makes the
floor safe to require rather than a workflow change.

Exceptions:

- `ci.yml`'s container-validation job keeps a `services:` block on
  purpose (it needs valkey published beyond loopback for
  `host.docker.internal`).
- `devcontainer-ci.yml` and `installer.yml` run `rake spec:fast` raw
  (via `pnpm run test:rspec:fast`): their environments cannot run
  `compose.test.yml` (the devcontainer can't nest containers; macOS
  runners have no container runtime), and the runner's preflight
  requires every endpoint in the lane's env — including rabbitmq — to
  be reachable. They prove `bin/setup` on constrained environments, not
  the lane contract. Tracked in #3982.
