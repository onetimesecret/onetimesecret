# Test Lanes

A lane is the supported contract for running a Ruby test suite: one named
execution environment, one process boundary, and one CI job or matrix row.
`tests/lanes/` and the root `compose.test.yml` define the services and
environment required by those tests. Run tests through `tests/lanes/run` so
local and CI execution use that contract.

## Quick start

```console
$ docker compose -f compose.test.yml up --wait -d   # or: podman compose
$ tests/lanes/run --list
$ tests/lanes/run unit
$ tests/lanes/run full-pg --overlay billing
$ tests/lanes/run --which spec/api/v2                # which lane runs a path
$ tests/lanes/run --only spec/api/v2/secret_ttl_entitlement_spec.rb:20   # one example, lane inferred
$ tests/lanes/run-all --parallel
$ tests/lanes/run-all --parallel --changed           # lanes owning the diff since origin/main
$ tests/lanes/run full-sqlite --console              # app console on the lane's datastore
$ docker compose -f compose.test.yml down
```

Prerequisites: bash 5+, `bundle install`, `pnpm install`, and `python3`.
macOS's system bash is 3.2; install a newer version with `brew install bash`.
`unit` and `smoke` also require built frontend assets in `public/web/dist/`
(`pnpm run build` locally; CI supplies them). `browser` also requires the
Playwright browser binaries (`pnpm exec playwright install chromium firefox
webkit`; `bin/setup --test` installs them) and, on Linux, their OS packages
(`pnpm exec playwright install-deps`, which uses sudo/apt and is therefore
left to the contributor and to CI). The lane's tasks preflight the binaries
and fail with that command when one is missing.

### Iterating on one file: `--only`

`--only <path>` runs one or more test files in a lane's environment without
running that lane's `tasks` file:

```console
$ tests/lanes/run simple --only apps/api/domains/spec/integration/simple/domain_sso_config_spec.rb
$ tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb:145
$ tests/lanes/run unit --only try/logic/sso_config/ssrf_protection_transition_try.rb
$ tests/lanes/run --only spec/api/v2/secret_ttl_entitlement_spec.rb:20          # lane inferred: api
```

- The lane is the one whose tasks run the file (`--which`, below). Leave the
  lane out and the runner infers it from the path; when several lanes run the
  path (`spec/integration/full` is run by `full-sqlite`, `full-pg` and
  `full-pg-agnostic`, split by tag) it exits 64 listing them, and when no
  lane runs it (`try/web`, a docs file) it exits 64 saying so — name the lane
  to run the file there anyway. Several `--only` paths must agree on one lane.
- `*_try.rb` files use `try --agent`; other files use `rspec`. Do not mix both
  kinds in one invocation. A directory is a valid path (rspec loads it).
- `path:LINE` selects an RSpec example.
- `--only` preserves the lane's isolation and environment guarantees, but skips
  generated prerequisites and every other task. Run the complete lane before
  pushing; CI validates lanes, not individual files.

For agents and humans alike: the first command on a CI failure is
`tests/lanes/run --only <path>:<LINE>` with the path and line from the CI
log (the lane is inferred); the full lane runs once, before the push.

#### Which lane runs a file: `--which`

```console
$ tests/lanes/run --which spec/api/v2
api
$ tests/lanes/run --which apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb
full-sqlite
full-pg
full-pg-agnostic
$ tests/lanes/run --which lib/onetime/session.rb
note: 'lib/onetime/session.rb' is shared by every lane
api
disabled
...
$ tests/lanes/run --which try/web/core/x_try.rb
error: no lane runs 'try/web/core/x_try.rb' (see tests/lanes/ownership)
```

One lane per line, exit 64 when no lane runs the path. The answer comes from
`tests/lanes/ownership`, a sourced bash table that transcribes the directory
conventions the lanes' rake tasks dispatch on (`lib/tasks/spec.rake`), per
lane — the same table lane inference and `run-all --changed` read, so the
three cannot disagree. Ownership is directory-level, as the tasks are:
inside `spec/integration/full` the `postgres_database` tag decides which of
the three full lanes runs an example, and the table names all three.
Support files (`spec/support`, an app's `spec/support`, `spec/spec_helper.rb`,
`try/support`) and application code (`lib/`, `apps/*` outside test trees,
`config/`, `etc/`, `locales/`, `Gemfile.lock`, `tests/lanes/`) are *shared*:
every lane but `smoke` runs them. The `selftest` lane checks the table
against every lane's tasks file and every `spec/` and `try/` directory on
disk, so a directory no lane claims fails there rather than running nowhere.

#### rspec passthrough: `-- <args>`

Everything after `--` is forwarded to rspec verbatim, never to tryouts. It
requires `--only`; a tryouts target combined with `--` exits 64.

```console
$ tests/lanes/run simple --only apps/api/domains/spec/integration/simple -- --only-failures
$ tests/lanes/run simple --only apps/api/domains/spec/integration/simple -- --next-failure
$ tests/lanes/run full-sqlite --only spec/integration/full -- -e 'rejects a stale token'
```

`--only-failures` and `--next-failure` work because the runner points rspec's
example-status file at `tmp/lanes/<lane>/<overlays>/rspec-status.txt`
(`base` when no overlay is set; gitignored; `--print-key` prints the path).
Every rspec run in that lane, full or `--only`, updates the file, so a full
lane run followed by `--only <dir> -- --only-failures` reruns exactly the
failures the lane recorded. Plain rspec outside the runner leaves
`LANES_RSPEC_STATUS_FILE` unset and records nothing.

### Quiet output: `--quiet`

```console
$ tests/lanes/run full-sqlite --quiet
$ tests/lanes/run simple --quiet --only apps/api/domains/spec/integration/simple
```

`--quiet` makes every rspec invocation in the run print failures (with their
diffs and rerun lines), pending examples and the summary — nothing per
passing example. It works by exporting `SPEC_OPTS` to select
`tests/lanes/support/quiet_formatter.rb`; rspec reads `SPEC_OPTS` after
`.rspec` and after the command line, so one variable covers the rake tasks
and `--only` alike. Without the flag `SPEC_OPTS` is not set and the output
is exactly what it was, which is what CI logs.

Tryouts legs need no switch: `try:unit`, `try:integration:simple` and
`--only` on a `*_try.rb` file already pass `--agent` outside CI.

The one trade-off: the `--format` in `SPEC_OPTS` replaces the rake tasks'
whole formatter list, including `--format json --out $RSPEC_OUTPUT_FILE`.
A run with `RSPEC_OUTPUT_FILE` set (CI plumbing) therefore rejects `--quiet`
with exit 64 rather than silently writing no results file.

### Last run output: `tmp/lanes/<lane>/<overlays>/last.log`

Every run, full lane or `--only`, is also written to
`tmp/lanes/<lane>/<overlays>/last.log` (`base` when no overlay is set; the
same directory as the rspec status file, gitignored). The file is truncated
at the start of each run, seeded with the run's banner line, and the runner
prints the absolute path with the exit code as its last line, on success and
on failure — the same line also ends the log itself, after the mid-run
service-loss verdict when there is one, so the file says how the run ended:

```text
[lane:simple] log: /path/to/checkout/tmp/lanes/simple/base/last.log (exit 1)
```

The task's stderr joins its stdout in the log, so the two streams arrive in
order rather than as separate outputs. The exit code is the task's, read
through the tee, so a red run stays red. When the runner's own stdout is a
terminal it sets `--force-color` (rspec) and `FORCE_COLOR` (tryouts) so
colors survive the pipe; the log then contains the escape codes too
(`less -R`). CI and `run-all` pipe the runner and get plain output as
before.

### Wall-clock per phase

Every run (full lane or `--only`, in every output mode) ends with one line
on stderr, just above the log line, giving the wall-clock of each phase:

```text
[lane:simple] time: preflight 1.2s codegen 4.6s tasks 198.2s (total 204.0s)
[lane:unit] time: preflight 0.5s codegen skipped only 7.2s (total 7.8s)
```

`preflight` is everything before the codegen phase: argument handling, the
service probes and autostart, the owner marker and liveness token, and the
PostgreSQL database and RabbitMQ vhost provisioning. `codegen` is the
lane's `LANES_CODEGEN` phase, `skipped` when it did not run (`--only`,
`--skip-codegen`, or a lane that declares none). The third phase is the
lane's `tasks` file or the `--only` command, measured around the process
through the `tee` into `last.log`. Tenths of a second, from `EPOCHREALTIME`.
The line is not in `last.log` (it is the runner's, not the task's output).

### Lane console: `--console`

```console
$ tests/lanes/run full-sqlite --console
$ tests/lanes/run full-pg --overlay billing --console
$ echo 'puts Familia.uri' | tests/lanes/run simple --console     # non-interactive
```

`--console` starts the app console (`bin/ots console`, the command behind
`bin/console`) in the lane's environment instead of running its tasks: the
same scrub, `base.env` -> lane `env` -> overlays, the same derived datastore
index (`REDIS_URL`, `AUTH_DATABASE_URL` and `RABBITMQ_URL` rewritten to it,
the PostgreSQL database and vhost provisioned), the same liveness token and
the same `env -u` strip at the exec. `--print-key` for the same lane and
overlays reports the addressing the console will see, so a question about
what a lane's specs left in the datastore is asked of that datastore and
nothing else. A plain `bin/console` inherits the shell, direnv included,
which is how test-mode settings have leaked before.

A console is not a run: it skips the codegen phase like `--only` (a missing
generated locale is a logged line at boot, not a failure), leaves
`last.log` untouched, and prints no timing line. It takes the lane name and
overlays only; `--only`, `--quiet`, `--skip-codegen` and `--` exit 64 with
it. Under `sqlite::memory:` (`full-sqlite`, `full-mfa`,
`full-saml-platform`) the auth database is empty and unmigrated in a fresh
process, so the console logs `no such table: accounts` at boot; the
PostgreSQL lanes address the per-worktree database the lane's runs use.

## Lanes

| Lane                | Services                   | Runs                                                       | CI job                                   |
| ------------------- | -------------------------- | ---------------------------------------------------------- | ---------------------------------------- |
| `unit`              | valkey, rabbitmq           | `try:unit`, `spec:fast`                                    | ruby-unit (T2)                           |
| `browser`           | valkey, rabbitmq           | `rspec tests/browser` (Playwright: chromium, firefox, webkit) | ruby-unit (T2) — browser lane step    |
| `simple`            | valkey, rabbitmq           | `try:integration:simple`, `spec:integration:simple`        | ruby-integration-simple (T3)             |
| `full-sqlite`       | valkey, rabbitmq           | `spec:integration:full`                                    | ruby-integration-full — SQLite rows      |
| `full-mfa`          | valkey, rabbitmq           | `spec:integration:full:mfa`                                | ruby-integration-full — SQLite MFA row   |
| `full-saml-platform` | valkey, rabbitmq          | `spec:integration:full:saml_platform`                      | ruby-integration-full — SQLite platform SAML row |
| `full-pg`           | valkey, rabbitmq, postgres | `spec:integration:full:postgres`                           | ruby-integration-full — PG rows          |
| `full-pg-agnostic`  | valkey, rabbitmq, postgres | `spec:integration:full:agnostic_on_pg`                     | ruby-integration-full — PG agnostic rows |
| `disabled`          | valkey, rabbitmq           | `spec:integration:disabled`                                | ruby-integration-disabled (T3)           |
| `api`               | valkey, rabbitmq           | `spec:api`                                                 | blocking step, T3 simple job             |
| `smoke`             | valkey, rabbitmq           | `pnpm test:smoke`                                          | local-only                               |
| `migrations-sqlite` | valkey, rabbitmq           | `spec:integration:migrations:sqlite`                       | migration-tests.yml — SQLite job         |
| `migrations-pg`     | valkey, rabbitmq, postgres | `spec:integration:migrations:postgres` plus dual-URL check | migration-tests.yml — PostgreSQL job     |
| `selftest`          | none                       | boundary fixture                                           | none — driven by `spec/unit/lanes/`      |

Start every service named for a lane. This includes RabbitMQ for `api`,
`browser` and `smoke`, whose lane environment still declares its endpoint.
`selftest` is the only service-free exception.

A lane with several legs (`unit`, `simple`, `migrations-pg`) runs every leg
even when an earlier one fails, then exits non-zero naming the red legs; the
same holds for the three rspec legs inside `rake spec:fast`. A red leg never
silently skips the ones after it.

Use `--overlay billing` only with full-mode lanes. Billing requires
`AUTHENTICATION_MODE=full`; other lanes reject the overlay.

Create a lane when a change selects a different test suite or a materially
different runtime (such as authentication mode or database engine). Use an
overlay for an environment-only toggle. Vitest, lint, and type checking do not
need lane services or environment, so run them with pnpm directly.

## Service safety boundary

Test services bind only to `127.0.0.1` ports beginning with `21`. Development
services retain their canonical ports, so lane configuration cannot target a
development datastore by accident.

| Service                 | Test port | Canonical port |
| ----------------------- | --------- | -------------- |
| valkey                  | 2163      | 6379           |
| postgres                | 2154      | 5432           |
| rabbitmq (AMQP)         | 2156      | 5672           |
| rabbitmq management API | 12156     | 15672          |

Define mappings only in `compose.test.yml`. Lane URLs use `21xx` service
ports; the runner-only RabbitMQ management endpoint is the loopback-only
`12156` exception. Any other endpoint is a safety defect.

## Per-worktree datastore isolation

Outside CI, lanes isolate each checkout—including Git worktrees—from sibling
checkouts while sharing the local test service instances:

- Valkey uses a deterministic index (`1..65535`) derived from the lane,
  normalized overlay set, and checkout root, exposed as `LANES_DATASTORE_DB`.
  Its host and port remain the test service.
- PostgreSQL uses the corresponding `onetime_auth_test_w<index>` database.
- RabbitMQ uses the corresponding `w<index>` vhost. The runner recreates and
  grants the vhost through RabbitMQ's loopback-only management API before a
  lane starts, preventing stale queues/messages from a prior run.
- CI and direct rspec commands outside the lane runner use the shared index,
  database, and vhost (`0` / `onetime_auth_test` / `/`). Do not rely on that
  mode for concurrent local worktrees. Direct TRYOUT commands are the
  exception on the Valkey axis only: `try/support/test_helpers.rb` derives a
  per-checkout index of its own (key `try||<root>`, see
  `try/support/datastore_db.rb`, which `pnpm run test:database:clean` also
  consults so cleanup reaches that database) — but they still share
  `onetime_auth_test` and the `/` vhost.
- A collision between derived Valkey indexes fails loudly rather than allowing
  fixture contamination. Pin `LANES_DATASTORE_DB` in a lane `env` file or an
  overlay if the runner reports a collision; a shell export is intentionally
  ignored.
- Worktree PostgreSQL databases persist after the worktree is deleted. To
  identify stale databases, review this query's output before executing any
  generated `DROP DATABASE` statements:

  ```console
  $ psql -h 127.0.0.1 -p 2154 -U onetime_migrator -d postgres -tAc \
      "SELECT 'DROP DATABASE ' || quote_ident(datname) || ';' \
         FROM pg_database WHERE datname LIKE 'onetime_auth_test\\_w%'"
  ```

The shared `onetime_auth_test` database does not match this query.

## Hermetic environment boundary

`tests/lanes/run` does not inherit development-shell configuration. It creates
a test environment from `base.env`, the selected lane's `env`, and requested
overlays. This protects test behavior and datastores from ambient variables,
including connection URLs and application feature settings.

Only these caller variables are retained:

```text
PATH HOME CI LANES_NO_AUTOSTART RSPEC_OUTPUT_FILE COVERAGE
```

Consequences for callers:

- Put required test configuration in `base.env` (all lanes) or a lane `env`
  file (one lane). Do not add application configuration to the retained list.
- Container-client connection settings are used only to start services; they
  are not exposed to the test process.
- Exported shell functions are not available inside lanes.
- `NODE_ENV=test` and `TZ=UTC` are lane invariants. Interactive lane shells
  receive them too; locale settings are constrained only for runner execution.
- Set `LANES_DEBUG_ENV=1` to print removed variables and exported functions.
  A listed variable must be declared in lane configuration, not exempted.

For interactive work, enter a lane directory and run `direnv allow` once. The
lane shell intentionally excludes the repository's development environment.
To enable a local, gitignored overlay for that shell, write its name to
`.overlays`, for example `echo billing > .overlays`.

## Parallel local runs

`tests/lanes/run-all` composes direct lane runs. With no lane names it runs
`unit simple disabled full-sqlite`; use `--parallel` to fan them out:

```console
$ docker compose -f compose.test.yml up --wait -d
$ tests/lanes/run-all --parallel
$ tests/lanes/run-all --parallel unit full-sqlite
```

It generates the union of requested `LANES_CODEGEN` prerequisites once before
starting children, then starts each child with `--skip-codegen`. This prevents
parallel writes to shared `generated/` files. Logs and RSpec JSON results are
written below `tmp/lanes/<timestamp>-<pid>/`; use `--dry-run` to inspect the
plan without generating or running tests.

`--parallel` requires test services to already be running and is rejected when
`CI` is set. It also rejects a duplicate lane: two copies derive the same
isolation key and would share a datastore. The `smoke` lane is local-only and
cannot be used with `--parallel`, because its task regenerates locales itself
and can race with other lanes. Run it alone (normally
`tests/lanes/run smoke`).

### Only the lanes a change touches: `--changed`

```console
$ tests/lanes/run-all --parallel --changed
[run-all] changed: since origin/main (merge-base), plus uncommitted changes
[run-all] changed: api <- spec/api/v2/secret_ttl_entitlement_spec.rb (+2 more)
[run-all] changed: simple <- apps/api/v1/spec/integration/simple/x_spec.rb
[run-all] changed: 3 path(s) no lane runs, e.g. docs/x.md
[run-all] parallel: api simple
$ tests/lanes/run-all --parallel --changed origin/develop
$ tests/lanes/run-all --dry-run --changed         # selection only, nothing runs
```

`--changed [<base>]` replaces the lane list with the lanes that run the paths
changed since `<base>` — `git diff --name-only <base>...HEAD` (merge-base)
plus staged, unstaged and untracked files — resolved through
`tests/lanes/ownership` (see `--which`). The default base is `origin/main`,
or `main` when there is no remote. Every selection is printed with the first
path that caused it. One shared path (`lib/`, `Gemfile.lock`,
`tests/lanes/`, ...) selects every lane except `smoke`, and the plan says
which path did it. When no lane runs any changed path there is nothing to
run and the command exits 0 saying so — it never falls back to the default
set. Lane names cannot be combined with `--changed`. The `selftest` lane
exercises the selection with a stubbed diff (`LANES_CHANGED_STUB`, honored
only together with `--dry-run`; set without it, the command exits 64 rather
than run a substituted diff).

## Rules

1. Endpoints in this tree target only loopback test ports: application services
   use the `21xx` range, with RabbitMQ management as the runner-only `12156`
   exception.
2. Commit no real secrets. `base.env` contains public deterministic dummy
   values; real environment configuration remains outside the repository.
3. Each lane's `env` file declares generated prerequisites through
   `LANES_CODEGEN`; direct runs execute them, while `run-all` owns the shared
   one-time phase before children start.
4. Lanes define the test environment and workload. CI owns gating,
   parallelism, artifacts, and reporting policy.

## CI contract

Ruby suites in CI use the lane runner and `compose.test.yml`; local lane runs
therefore exercise the same service and environment contract. CI runs whole
lanes, never `--only`: a suite that CI needs is a lane (the `browser` lane
exists for that reason), so the command CI runs is the command a contributor
runs. Toolchain prerequisites a lane cannot generate — built frontend assets,
Playwright browsers — are installed by the CI job and by `bin/setup --test`;
the lane preflights them rather than installing them. The supported CI
exceptions are constrained environments that cannot run the compose topology:
`devcontainer-ci.yml` and macOS `installer.yml` run the fast suite directly.
They validate installation paths, not lane behavior.
