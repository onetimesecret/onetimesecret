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
$ docker compose -f compose.test.yml down
```

Prerequisites: bash 5+, `bundle install`, `pnpm install`, and `python3`.
macOS's system bash is 3.2; install a newer version with `brew install bash`.
`unit` and `smoke` also require built frontend assets in `public/web/dist/`
(`pnpm run build` locally; CI supplies them).

### Iterating on one file: `--only`

`--only <path>` runs one or more test files in a lane's environment without
running that lane's `tasks` file:

```console
$ tests/lanes/run simple --only apps/api/domains/spec/integration/simple/domain_sso_config_spec.rb
$ tests/lanes/run full-sqlite --only apps/web/auth/spec/integration/full/omniauth_csrf_spec.rb:145
$ tests/lanes/run unit --only try/logic/sso_config/ssrf_protection_transition_try.rb
```

- Choose the lane expected by the file. For example, a full-integration spec
  requires a full lane's authentication configuration.
- `*_try.rb` files use `try --agent`; other files use `rspec`. Do not mix both
  kinds in one invocation.
- `path:LINE` selects an RSpec example.
- `--only` preserves the lane's isolation and environment guarantees, but skips
  generated prerequisites and every other task. Run the complete lane before
  pushing; CI validates lanes, not individual files.

## Lanes

| Lane                | Services                   | Runs                                                       | CI job                                   |
| ------------------- | -------------------------- | ---------------------------------------------------------- | ---------------------------------------- |
| `unit`              | valkey, rabbitmq           | `try:unit`, `spec:fast`                                    | ruby-unit (T2)                           |
| `simple`            | valkey, rabbitmq           | `try:integration:simple`, `spec:integration:simple`        | ruby-integration-simple (T3)             |
| `full-sqlite`       | valkey, rabbitmq           | `spec:integration:full`                                    | ruby-integration-full — SQLite rows      |
| `full-pg`           | valkey, rabbitmq, postgres | `spec:integration:full:postgres`                           | ruby-integration-full — PG rows          |
| `full-pg-agnostic`  | valkey, rabbitmq, postgres | `spec:integration:full:agnostic_on_pg`                     | ruby-integration-full — PG agnostic rows |
| `disabled`          | valkey, rabbitmq           | `spec:integration:disabled`                                | ruby-integration-disabled (T3)           |
| `api`               | valkey, rabbitmq           | `spec:api`                                                 | blocking step, T3 simple job             |
| `smoke`             | valkey, rabbitmq           | `pnpm test:smoke`                                          | smoke-test (T3)                          |
| `migrations-sqlite` | valkey, rabbitmq           | `spec:integration:migrations:sqlite`                       | migration-tests.yml — SQLite job         |
| `migrations-pg`     | valkey, rabbitmq, postgres | `spec:integration:migrations:postgres` plus dual-URL check | migration-tests.yml — PostgreSQL job     |
| `selftest`          | none                       | boundary fixture                                           | none — driven by `spec/unit/lanes/`      |

Start every service named for a lane. This includes RabbitMQ for `api` and
`smoke`, whose lane environment still declares its endpoint. `selftest` is the
only service-free exception.

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

| Service  | Test port | Canonical port |
| -------- | --------- | -------------- |
| valkey   | 2163      | 6379           |
| postgres | 2154      | 5432           |
| rabbitmq | 2156      | 5672           |

Define mappings only in `compose.test.yml`. URLs in this tree must use a test
port; a non-`21xx` endpoint is a safety defect.

## Per-worktree datastore isolation

Outside CI, lanes isolate each checkout—including Git worktrees—from sibling
checkouts while sharing the local test service instances:

- Valkey uses a deterministic per-worktree database index (`1..65535`), exposed
  as `LANES_DATASTORE_DB`. Its host and port remain the test service.
- PostgreSQL uses a corresponding `onetime_auth_test_w<index>` database.
- CI and direct test commands outside the lane runner use the shared index or
  database (`0` / `onetime_auth_test`). Do not rely on that mode for concurrent
  local worktrees.
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

## Rules

1. Endpoints in this tree target only `127.0.0.1` test ports in the `21xx`
   range.
2. Commit no real secrets. `base.env` contains public deterministic dummy
   values; real environment configuration remains outside the repository.
3. Each lane's `tasks` file owns the generated prerequisites required for a
   complete lane run.
4. Lanes define the test environment and workload. CI owns gating,
   parallelism, artifacts, and reporting policy.

## CI contract

Ruby suites in CI use the lane runner and `compose.test.yml`; local lane runs
therefore exercise the same service and environment contract. The supported CI
exceptions are constrained environments that cannot run the compose topology:
`devcontainer-ci.yml` and macOS `installer.yml` run the fast suite directly.
They validate installation paths, not lane behavior.
