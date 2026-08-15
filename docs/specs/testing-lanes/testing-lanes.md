# Testing Lanes Design

## Purpose

Test lanes define the supported execution environments for Ruby tests. A lane
is one process boundary and normally one CI job or matrix row. The design
keeps local and CI test behavior aligned while protecting developer data and
isolating concurrent worktrees.

The caller-facing interface is documented in [`tests/lanes/README.md`](../../../tests/lanes/README.md).
This document records the design decisions and invariants that must remain true
when changing the lane runner, lane definitions, compose topology, or CI
integration.

## Architecture and ownership

`tests/lanes/` and the root `compose.test.yml` are the single source of truth
for what a lane needs. CI and local execution enter through
`tests/lanes/run`.

| Component | Responsibility |
| --- | --- |
| `compose.test.yml` | Test service images, ports, and published endpoints |
| `tests/lanes/base.env` | Environment shared by every lane |
| `tests/lanes/<lane>/env` | Lane-specific environment |
| `tests/lanes/<lane>/tasks` | The complete workload and generated prerequisites for a lane |
| `tests/lanes/overlays/` | Environment-only variations, such as billing |
| `tests/lanes/run` | Hermetic environment, service preflight, datastore isolation, and execution |
| `.envrc` files | Interactive lane environment; never the development environment |
| CI workflows | Gating, parallelism, artifacts, and reporting |

A lane directory represents a dimension that changes the test workload or
runtime topology, such as authentication mode or database engine. An overlay
represents an environment-only toggle. Do not create a lane for every overlay
combination: that duplicates the lane tree and obscures which dimension selects
specs.

## Lane taxonomy

| Lane | Services | Runs | CI job |
| --- | --- | --- | --- |
| `unit` | valkey, rabbitmq | `try:unit`, `spec:fast` | ruby-unit (T2) |
| `simple` | valkey, rabbitmq | `try:integration:simple`, `spec:integration:simple` | ruby-integration-simple (T3) |
| `full-sqlite` | valkey, rabbitmq | `spec:integration:full` | ruby-integration-full — SQLite rows |
| `full-pg` | valkey, rabbitmq, postgres | `spec:integration:full:postgres` | ruby-integration-full — PG rows |
| `full-pg-agnostic` | valkey, rabbitmq, postgres | `spec:integration:full:agnostic_on_pg` | ruby-integration-full — PG agnostic rows |
| `disabled` | valkey, rabbitmq | `spec:integration:disabled` | ruby-integration-disabled (T3) |
| `api` | valkey, rabbitmq | `spec:api` | blocking step, T3 simple job |
| `smoke` | valkey, rabbitmq | `pnpm test:smoke` | smoke-test (T3) |
| `migrations-sqlite` | valkey, rabbitmq | `spec:integration:migrations:sqlite` | migration-tests.yml — SQLite job |
| `migrations-pg` | valkey, rabbitmq, postgres | `spec:integration:migrations:postgres` plus dual-URL check | migration-tests.yml — PostgreSQL job |
| `selftest` | none | boundary fixture | none — driven by `spec/unit/lanes/` |

Every endpoint declared by a lane is preflighted, even when the resulting test
workload does not directly use that service. Therefore `api` and `smoke` still
require RabbitMQ: `base.env` declares `RABBITMQ_URL` for all lanes. `selftest`
clears all service URLs and is the deliberate exception.

Billing is an overlay on full-mode lanes only. It requires
`AUTHENTICATION_MODE=full`; the runner rejects it elsewhere. Frontend Vitest,
lint, and type checking have no lane because they require neither lane services
nor lane environment.

## Safety invariants

The following invariants protect local developer state and make local results
comparable with CI:

1. Test endpoints are loopback-only and use the test-port scheme below.
2. Lane configuration contains no real secrets. Committed `base.env` values are
   public deterministic dummies; real configuration stays outside the repo.
3. A complete lane run obtains its generated prerequisites from that lane's
   `tasks` file. Do not move those prerequisites to CI-only setup.
4. Application test configuration originates in lane environment files, not the
   caller's shell.
5. CI policy is not lane policy. Lanes define the environment and workload;
   workflows decide whether a failure blocks, how work is parallelized, and how
   results are reported.

### Test service ports

Every test service is published only on `127.0.0.1` with a `21xx` port.
Development services retain their canonical ports. This creates a separate
address space: leaked development configuration cannot reach test services, and
lane configuration cannot reach development datastores.

New test services use `21` followed by the last two digits of their canonical
port. Valkey predates this convention and retains `2163`.

| Service | Test port | Canonical port |
| --- | --- | --- |
| valkey | 2163 | 6379 |
| postgres | 2154 | 5432 |
| rabbitmq | 2156 | 5672 |

Port mappings belong only in `compose.test.yml`; lane environment files carry
matching URLs. A URL in this tree that does not use a `21xx` port violates the
isolation boundary.

## Per-worktree datastore isolation

Local worktrees share test service instances. They must not share fixtures.
Outside CI, the runner derives a deterministic index from the repository root
and assigns it to both datastores. The index range is `1..8191`; Valkey is
configured with 8192 databases.

| Datastore | Shared mode | Per-worktree mode |
| --- | --- | --- |
| Valkey | database `0` | database index `1..8191` |
| PostgreSQL | `onetime_auth_test` | `onetime_auth_test_w<index>` |

The index is exported as `LANES_DATASTORE_DB`. `spec/config.test.yaml` uses it
for `redis.uri`, and the runner aligns `REDIS_URL` and `VALKEY_URL`. This
selects a database on the existing test service; it must never alter the host
or port.

### Shared mode and explicit assignment

Index `0` disables per-worktree isolation. CI uses it because each job owns its
services and the shared PostgreSQL database name is used by workflow steps.
Direct test commands outside the runner also use shared mode.

A lane `env` file or overlay may explicitly pin `LANES_DATASTORE_DB`. The
caller's shell may not: the hermetic boundary removes it. The runner verifies
that the Valkey service supports the selected index and reports the default
16-database configuration as a setup error.

### Valkey collision detection

The deterministic mapping can collide. A collision must fail rather than let
two worktrees contaminate each other's fixtures.

The runner stores an owner marker, `_lanes:owner`, containing the repository
root in the selected Valkey database. It claims a fresh marker atomically with
`SET NX`. A live owner from another checkout aborts the run and requires an
explicit index pin. If the recorded checkout no longer exists, the runner may
take over the stale marker and verifies the takeover.

There is intentionally no on-disk registry, reclamation process, or
cross-process file lock. The datastore is the shared coordination point. The
marker is removed by `pnpm clean:db` and is re-established by the next lane
run.

Inspect an owner with:

```console
$ valkey-cli -p 2163 -n <index> get _lanes:owner
```

### PostgreSQL provisioning and lifecycle

Per-worktree PostgreSQL isolation uses a database, not a schema. The existing
`onetime_migrator` role has `CREATEDB` and owns databases it creates, allowing
it to install `citext` and run `initialize_test_db.sql`, including
`DROP SCHEMA public CASCADE`, without a superuser.

Schemas would require per-schema grants, default privileges, and a
`search_path` on every connection, including Rodauth's. They would also test a
topology production does not use. Separate databases reuse the existing
cluster-scoped roles and exercise the migration and permission model directly.

`tests/lanes/support/provision_pg_database.rb` creates and initializes a
worktree database on its first PostgreSQL lane run. It holds a PostgreSQL
advisory lock across the operation so simultaneous runs cannot observe a
partially provisioned database. If initialization fails, it drops the database
instead of leaving an incomplete database that a later run could accept.

Worktree PostgreSQL databases persist after their worktrees are removed. To
identify stale databases, review this output before executing any generated
`DROP DATABASE` statements:

```console
$ psql -h 127.0.0.1 -p 2154 -U onetime_migrator -d postgres -tAc \
    "SELECT 'DROP DATABASE ' || quote_ident(datname) || ';' \
       FROM pg_database WHERE datname LIKE 'onetime_auth_test\\_w%'"
```

The shared `onetime_auth_test` database does not match this query.

## Hermetic execution boundary

The runner removes caller environment variables and exported shell functions,
then builds the test environment from `base.env`, the selected lane's `env`,
and requested overlays. This is an allowlist design: a denylist cannot safely
anticipate future connection settings, feature flags, or application settings
that might alter tests.

The exact retained caller variables are:

```text
PATH HOME CI LANES_NO_AUTOSTART RSPEC_OUTPUT_FILE COVERAGE
```

Each allowlisted name must remain justified as toolchain resolution or CI
plumbing. Application configuration belongs in `base.env` or a lane `env` file,
not this list.

### Runner ordering

The scrub is the runner's first substantive operation and must stay before
script-local assignments. Bash preserves an existing export attribute when a
script assigns the same variable name; a variable set before the scrub could be
removed as caller state and later be unbound. Keep new runner variables below
the scrub boundary.

The boundary also removes exported functions. Bash otherwise restores them in
an executed task process, permitting a caller profile, direnv setup, or shell
shim to shadow commands such as `git`, `bundle`, `docker`, `podman`, or `rake`.

### Bash compatibility

The scrub uses Bash 5 features, including `mapfile` and reliable empty-array
expansion under `set -u`. The required version is defined once in the root
`.bash-version`; `tests/lanes/run`, `bin/setup --doctor`, and the hermetic
boundary spec must read that file rather than duplicate the version.

The runner must reject older Bash before entering the boundary. `bin/setup`
remains Bash 3.2-compatible because it must run on macOS before a contributor
can install a newer Bash.

### Container clients

Container-client connection variables, including `DOCKER_HOST`,
`DOCKER_CONTEXT`, `DOCKER_CONFIG`, `CONTAINER_HOST`, and `XDG_RUNTIME_DIR`,
are deliberately excluded from the test environment. The runner preserves them
only long enough to invoke `docker compose` or `podman compose` for service
autostart. This supports non-default daemons such as Colima, OrbStack, and
rootless Podman without leaking container connection state into tests.

### Determinism and interactive shells

`NODE_ENV=test` and `TZ=UTC` are in `base.env`. They affect observable test
behavior and are intentionally also present in an interactive lane shell.
`LANG` and `LC_ALL` are set by the runner instead: locale is an execution
concern and must not silently alter every shell that enters a lane directory.

Lane `.envrc` files intentionally do not source upward past `tests/lanes/`.
An interactive lane shell therefore represents the lane environment rather than
the development environment. A gitignored `.overlays` file supplies optional
interactive overlays.

`LANES_DEBUG_ENV=1` is a diagnostic runner input. It reports every removed
variable and exported function; use that output to place required configuration
in lane files rather than extending the allowlist.

## Execution semantics

`--only` is a fast path through the same hermetic environment and datastore
isolation, but it skips the lane's `tasks` file. It is therefore unsuitable as
the final validation of a change when that file owns generated prerequisites.

The runner dispatches `*_try.rb` files to `try --agent` and all other files to
RSpec. It accepts RSpec's `path:LINE` form. One invocation must contain only
one runner type.

## CI integration

Ruby test suites enter through lanes and `compose.test.yml`:

- `.github/workflows/ci.yml` uses the `run-test-lane` composite action for Ruby
  jobs. The composite adds CI-only failure-tail comments and job summaries;
  `ci.yml` supplies `COVERAGE` through `GITHUB_ENV`. Full-mode matrix rows are
  lane and overlay combinations.
- `.github/workflows/migration-tests.yml` runs the `migrations-*` lanes through
  the same composite. Its concurrent-boot job is intentionally CI
  orchestration, not a lane, although it uses `compose.test.yml` services.
- `.github/workflows/ruby-4-preview.yml` invokes lanes directly because it is
  advisory and does not need the composite's result plumbing.
- `.github/workflows/fresh-clone.yml` invokes `unit` directly after
  `bin/setup --test`, validating the documented contributor path.

Lane CI jobs run on Ubuntu 24.04, which satisfies the Bash 5 requirement.
The macOS installer workflow does not enter a lane.

Two constrained-environment exceptions are intentional:

- `ci.yml`'s container-validation job keeps its own `services:` block because
  it needs Valkey published beyond loopback for `host.docker.internal`.
- `devcontainer-ci.yml` and `installer.yml` run the fast suite directly. The
  devcontainer cannot nest containers, and macOS runners have no container
  runtime. These jobs validate installation paths, not the lane contract.
