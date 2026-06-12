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

Prerequisites: `bundle install`, `pnpm install`, `python3` (locale
compilation). Lanes whose specs read built frontend assets (`unit`,
`smoke`) need `public/web/dist/` populated — `pnpm run build` locally;
CI provides it as a build artifact.

## Lanes

| Lane              | Services                   | Runs                                                  | CI job                                  |
| ----------------- | -------------------------- | ----------------------------------------------------- | --------------------------------------- |
| `unit`            | valkey, rabbitmq           | `try:unit`, `spec:fast`                               | ruby-unit (T2)                          |
| `simple`          | valkey, rabbitmq           | `try:integration:simple`, `spec:integration:simple`   | ruby-integration-simple (T3)            |
| `full-sqlite`     | valkey, rabbitmq           | `spec:integration:full`                               | ruby-integration-full — SQLite rows     |
| `full-pg`         | valkey, rabbitmq, postgres | `spec:integration:full:postgres`                      | ruby-integration-full — PG rows         |
| `full-pg-agnostic`| valkey, rabbitmq, postgres | `spec:integration:full:agnostic_on_pg`                | ruby-integration-full — PG agnostic rows|
| `disabled`        | valkey, rabbitmq           | `spec:integration:disabled`                           | ruby-integration-disabled (T3)          |
| `api`             | valkey                     | `spec:api`                                            | non-blocking step, T3 simple job        |
| `smoke`           | valkey                     | `pnpm test:smoke`                                     | smoke-test (T3)                         |

The billing matrix rows are the same lanes with `--overlay billing`.

Directories exist for dimensions that change **which specs run** (auth
mode, database engine — mirroring `spec/integration/{simple,full,disabled}`).
Overlays exist for dimensions that only change **environment**
(billing on/off). Adding a full directory per combination would double
the tree per toggle; don't.

Vitest, lint, and type-check need no services or special env, so they
have no lanes — run them via pnpm directly.

## Ports: the 21 rule

Every test service publishes on `127.0.0.1` with a port starting with
21 — "21 + last two digits of the canonical port". Dev services keep
canonical ports. A leaked dev config therefore cannot reach a test
service, and a test run cannot reach dev data. This plus the hermetic
runner is the answer to "tests wiped my dev database".

| Service  | Test port | Canonical |
| -------- | --------- | --------- |
| valkey   | 2121      | 6379      |
| postgres | 2132      | 5432      |
| rabbitmq | 2172      | 5672      |

Port mappings are defined **only** in `compose.test.yml`. The env files
here carry matching URLs; if a URL in this tree doesn't point at a 21xx
port, that's a bug.

## Hermetic runs vs. interactive shells

`tests/lanes/run` clears every mode/endpoint variable the lane files own
before loading `base.env` -> `<lane>/env` -> overlays. A test run behaves
identically whether launched from a dev shell, a lane directory, or CI.

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
   reporting) belongs to CI. Lanes define *what runs in which
   environment*; the workflow decides what it means when a lane fails.

## CI adoption status

`.github/workflows/ci.yml` does not consume this tree yet. Migration:
replace each Ruby job's `services:` block with
`docker compose -f compose.test.yml up --wait` and its env/composite-action
wiring with `tests/lanes/run <lane>` (matrix rows become lane names +
overlays). Until then, CI still runs services on canonical ports — the
tree is the target state, adopted job by job.
