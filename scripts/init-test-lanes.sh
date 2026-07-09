#!/usr/bin/env bash
#
# scripts/init-test-lanes.sh
#
# Scaffolds the committed test-lane structure that gives local dev <=> CI
# parity. One lane = one process boundary = one CI job (or matrix row):
# a directory holding the lane's environment (env), what it runs (tasks),
# and a direnv hook (.envrc) for interactive work.
#
# Creates:
#   compose.test.yml            Test services on 127.0.0.1 ports starting
#                               with 21 (valkey 2121, postgres 2132,
#                               rabbitmq 2172), digest-pinned to match CI.
#   tests/lanes/base.env        Lane-invariant env: endpoints, dummy secrets.
#   tests/lanes/run             Hermetic lane runner (CI + local entrypoint).
#   tests/lanes/<lane>/         env + tasks + .envrc per lane:
#                               unit, simple, full-sqlite, full-pg,
#                               full-pg-agnostic, disabled, api, smoke
#   tests/lanes/overlays/       Env-only toggles (billing).
#   tests/lanes/README.md       The contract, lane table, and rules.
#
# Everything written here is meant to be committed: the tree contains no
# secrets (dummy values only) and is the single source of truth for "what
# environment do tests need". Real environment configuration (dev/staging/
# prod) stays in the external per-environment config system, as ever.
#
# Idempotent: existing files are left untouched. Use --force to overwrite.

set -euo pipefail

FORCE=0
case "${1:-}" in
  --force) FORCE=1 ;;
  '') ;;
  *) echo "usage: $0 [--force]" >&2; exit 64 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ ! -f Gemfile || ! -f package.json ]]; then
  echo "error: $ROOT does not look like an OTS checkout root" >&2
  exit 1
fi

created=()
skipped=()

# write_file <path>  (content on stdin)
write_file() {
  local path="$1"
  if [[ -e "$path" && $FORCE -eq 0 ]]; then
    skipped+=("$path")
    cat > /dev/null
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  created+=("$path")
}

# ============================================================================
# compose.test.yml — test service dependencies
# ============================================================================

write_file compose.test.yml <<'EOF'
# compose.test.yml — service dependencies for the test lanes.
#
# SINGLE SOURCE OF TRUTH for test service images, versions, and host ports.
# CI and local dev both start services from this file; the lane env files
# under tests/lanes/ carry the matching URLs.
#
#   docker compose -f compose.test.yml up --wait -d
#   podman compose -f compose.test.yml up --wait -d
#   docker compose -f compose.test.yml down
#
# PORT SCHEME: every test service publishes on 127.0.0.1 with a port that
# starts with 21. New services take "21 + last two digits of the canonical
# port"; valkey predates the scheme and keeps its established 2121:
#
#   valkey     2121   (canonical 6379; grandfathered, not 2179)
#   postgres   2132   (canonical 5432)
#   rabbitmq   2172   (canonical 5672)
#
# Dev services keep canonical ports, so a leaked dev config can never reach
# a test service and a test run can never reach dev data. If a URL in the
# test tree doesn't point at a 21xx port, that's a bug.
#
# Images are digest-pinned to the exact images CI uses
# (.github/workflows/ci.yml). Update both together.

name: ots-test

services:
  valkey:
    image: ghcr.io/valkey-io/valkey:8.1.3-bookworm@sha256:fea8b3e67b15729d4bb70589eb03367bab9ad1ee89c876f54327fc7c6e618571
    # No persistence: test data is disposable by design.
    command: ['valkey-server', '--save', '', '--appendonly', 'no']
    ports:
      - '127.0.0.1:2121:6379'
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 10s
      timeout: 10s
      retries: 5

  postgres:
    image: postgres:17@sha256:b994732fcf33f73776c65d3a5bf1f80c00120ba5007e8ab90307b1a743c1fc16
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: onetime_auth_test
    # Creates onetime_user/onetime_migrator roles (testpass/migratepass)
    # on first boot — the same SQL CI used to run as a separate psql step.
    volumes:
      - ./apps/web/auth/migrations/schemas/postgres/initialize_test_db.sql:/docker-entrypoint-initdb.d/10-initialize-test-db.sql:ro
    # Data lives in RAM: fast, and guaranteed gone on `down`.
    tmpfs:
      - /var/lib/postgresql/data
    ports:
      - '127.0.0.1:2132:5432'
    healthcheck:
      test: ['CMD', 'pg_isready', '-U', 'postgres']
      interval: 10s
      timeout: 10s
      retries: 5

  rabbitmq:
    image: rabbitmq:4.2@sha256:0ea64c69ef2ced52e7188c6db826152d42f78e448433ed8b4e570170c427a437
    ports:
      - '127.0.0.1:2172:5672'
    healthcheck:
      test: ['CMD', 'rabbitmq-diagnostics', 'check_port_connectivity']
      interval: 10s
      timeout: 10s
      retries: 5
EOF

# ============================================================================
# tests/lanes/base.env — lane-invariant environment
# ============================================================================

write_file tests/lanes/base.env <<'EOF'
# tests/lanes/base.env — lane-invariant test environment.
#
# Loaded first by every lane (by tests/lanes/run and by the per-lane
# .envrc). Lane env files and overlays override anything here.
#
# RULES
#   - Endpoints point only at 127.0.0.1 ports starting with 21. The port
#     mappings are defined once, in compose.test.yml. Never point anything
#     in this tree at a canonical-port (dev/prod) service.
#   - No real secrets, ever. The values below are public dummies committed
#     on purpose. Real environment config lives outside this repository.

RACK_ENV=test

# ── Service endpoints (provided by compose.test.yml) ────────────────────
REDIS_URL='redis://127.0.0.1:2121/0'
VALKEY_URL='valkey://127.0.0.1:2121/0'
RABBITMQ_URL='amqp://guest:guest@127.0.0.1:2172'

# Billing is off unless a lane runs with `--overlay billing`.
BILLING_ENABLED=false

# ── Fixed dummy secrets ──────────────────────────────────────────────────
# Same shape CI previously generated randomly per run (openssl rand -hex
# 32), but deterministic so every contributor and CI run is identical and
# secret-derived output is reproducible. OBVIOUSLY FAKE hex-word patterns;
# each value distinct. Do not replace with real values.
SECRET=decafbaddecafbaddecafbaddecafbaddecafbaddecafbaddecafbaddecafbad
SESSION_SECRET=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
AUTH_SECRET=cafef00dcafef00dcafef00dcafef00dcafef00dcafef00dcafef00dcafef00d
ARGON2_SECRET=feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface
ACCOUNT_ID_SECRET=0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff1ce0ff
FEDERATION_SECRET=baddcafebaddcafebaddcafebaddcafebaddcafebaddcafebaddcafebaddcafe
IDENTIFIER_SECRET=d00dfeedd00dfeedd00dfeedd00dfeedd00dfeedd00dfeedd00dfeedd00dfeed
EOF

# ============================================================================
# tests/lanes/.envrc — direnv parent for all lanes
# ============================================================================

write_file tests/lanes/.envrc <<'EOF'
# tests/lanes/.envrc — direnv parent for every lane directory.
#
# Deliberately does NOT source_up into the repo root .envrc: lane
# directories are isolated from the dev environment by design. cd'ing
# into a lane gives you that lane's environment and nothing else —
# this is half of the "tests can never touch dev data" guarantee
# (the other half is the 21xx port scheme; see README.md).
dotenv base.env
EOF

# ============================================================================
# tests/lanes/run — hermetic lane runner (CI + local entrypoint)
# ============================================================================

write_file tests/lanes/run <<'EOF'
#!/usr/bin/env bash
#
# tests/lanes/run — hermetic test lane runner.
#
# Usage:
#   tests/lanes/run --list
#   tests/lanes/run <lane> [--overlay <name>]...
#
# Examples:
#   tests/lanes/run unit
#   tests/lanes/run full-pg --overlay billing
#
# Runs a lane's tasks (tests/lanes/<lane>/tasks) with exactly the lane's
# environment, regardless of what the calling shell exported. CI and local
# development both enter through this script — that is the parity contract.
#
# Environment precedence (highest wins):
#   overlays > lane env > base.env > (nothing)
#
# "Nothing" is literal: every mode/endpoint variable the lane files own is
# cleared before loading, so a dev shell's REDIS_URL or AUTH_DATABASE_URL
# (direnv-loaded or otherwise) can never leak into a test run.

set -euo pipefail

LANES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LANES_DIR}/../.." && pwd)"

list_lanes() {
  local dir
  for dir in "${LANES_DIR}"/*/; do
    if [[ -f "${dir}tasks" && -f "${dir}env" ]]; then
      basename "${dir}"
    fi
  done
}

if [[ $# -eq 0 || "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
  echo "usage: tests/lanes/run <lane> [--overlay <name>]..."
  echo
  echo "Lanes:"
  list_lanes | sed 's/^/  /'
  echo
  echo "Overlays:"
  for f in "${LANES_DIR}"/overlays/*.env; do
    [[ -e "$f" ]] && basename "$f" .env | sed 's/^/  /'
  done
  exit 0
fi

LANE="$1"
shift
LANE_DIR="${LANES_DIR}/${LANE}"
if [[ ! -f "${LANE_DIR}/env" || ! -f "${LANE_DIR}/tasks" ]]; then
  echo "error: unknown lane '${LANE}' (see: tests/lanes/run --list)" >&2
  exit 64
fi

OVERLAYS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --overlay)
      [[ $# -ge 2 ]] || { echo "error: --overlay requires a name" >&2; exit 64; }
      [[ "$2" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "error: overlay name '$2' contains invalid characters" >&2; exit 64; }
      OVERLAYS+=("$2")
      shift 2
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      exit 64
      ;;
  esac
done

# Hermetic boundary: clear every variable the lane files own. Whatever
# direnv loaded for dev (or a previous lane) stops here.
unset RACK_ENV AUTHENTICATION_MODE BILLING_ENABLED ORGS_SSO_ENABLED \
      REDIS_URL VALKEY_URL RABBITMQ_URL \
      AUTH_DATABASE_URL AUTH_DATABASE_URL_MIGRATIONS \
      AUTH_DATABASE_URL_PG AUTH_DATABASE_URL_MIGRATIONS_PG \
      SECRET SESSION_SECRET AUTH_SECRET ARGON2_SECRET ACCOUNT_ID_SECRET \
      FEDERATION_SECRET IDENTIFIER_SECRET

set -a
# shellcheck source=/dev/null
source "${LANES_DIR}/base.env"
# shellcheck source=/dev/null
source "${LANE_DIR}/env"
if [[ ${#OVERLAYS[@]} -gt 0 ]]; then
  for name in "${OVERLAYS[@]}"; do
    overlay_file="${LANES_DIR}/overlays/${name}.env"
    if [[ ! -f "${overlay_file}" ]]; then
      echo "error: unknown overlay '${name}' (no ${overlay_file})" >&2
      exit 64
    fi
    # shellcheck source=/dev/null
    source "${overlay_file}"
  done
fi
set +a

echo "[lane:${LANE}] mode=${AUTHENTICATION_MODE:-?}" \
     "billing=${BILLING_ENABLED:-false}" \
     "redis=${REDIS_URL:-?}" \
     "auth_db=${AUTH_DATABASE_URL:-n/a}"

cd "${REPO_ROOT}"
exec bash -euo pipefail "${LANE_DIR}/tasks"
EOF

# ============================================================================
# Overlays — env-only toggles
# ============================================================================

write_file tests/lanes/overlays/billing.env <<'EOF'
# Overlay: billing — flips billing on for any lane.
#
#   tests/lanes/run full-sqlite --overlay billing
#   tests/lanes/run full-pg --overlay billing
#
# Overlays exist for dimensions that only change environment, not which
# specs run (those get their own lane directory). Billing specs replay
# committed VCR cassettes, so no Stripe key is needed here — recording
# new cassettes is a separate, explicitly-keyed task (rake vcr:billing:*).
BILLING_ENABLED=true
EOF

# ============================================================================
# Lane: unit
# ============================================================================

write_file tests/lanes/unit/env <<'EOF'
# Lane: unit — unit + app specs and unit tryouts (no auth-mode boundary).
# CI job: ruby-unit (T2)
AUTHENTICATION_MODE=simple
EOF

write_file tests/lanes/unit/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
#
# locales + JSON schemas are generated prerequisites: spec:fast includes
# the billing catalog spec that reads gitignored
# generated/schemas/config/billing.schema.json.
pnpm run locales:sync
pnpm run schemas:json:generate
bundle exec rake try:unit
bundle exec rake spec:fast
EOF

# ============================================================================
# Lane: simple
# ============================================================================

write_file tests/lanes/simple/env <<'EOF'
# Lane: simple — integration specs for AUTHENTICATION_MODE=simple.
# CI job: ruby-integration-simple (T3)
AUTHENTICATION_MODE=simple
EOF

write_file tests/lanes/simple/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake try:integration:simple
bundle exec rake spec:integration:simple
EOF

# ============================================================================
# Lane: full-sqlite
# ============================================================================

write_file tests/lanes/full-sqlite/env <<'EOF'
# Lane: full-sqlite — full auth mode against in-memory SQLite.
# CI job: ruby-integration-full (T3, "SQLite" matrix rows; billing via overlay)
#
# NOTE: lib/tasks/spec.rake hardcodes AUTH_DATABASE_URL/ORGS_SSO_ENABLED
# for this task as a defense against ambient env. Keeping identical values
# here is intentional: the lane is correct standalone (e.g. running rspec
# by hand from this directory), and rake's override is a no-op.
AUTHENTICATION_MODE=full
AUTH_DATABASE_URL='sqlite::memory:'
ORGS_SSO_ENABLED=true
EOF

write_file tests/lanes/full-sqlite/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake spec:integration:full
EOF

# ============================================================================
# Lane: full-pg
# ============================================================================

write_file tests/lanes/full-pg/env <<'EOF'
# Lane: full-pg — PostgreSQL-only full-mode specs (--tag postgres_database).
# CI job: ruby-integration-full (T3, "PG" matrix rows; billing via overlay)
#
# Roles and passwords come from apps/web/auth/migrations/schemas/postgres/
# initialize_test_db.sql, which compose.test.yml mounts into
# /docker-entrypoint-initdb.d/ (runs on first boot).
AUTHENTICATION_MODE=full
AUTH_DATABASE_URL='postgresql://onetime_user:testpass@127.0.0.1:2132/onetime_auth_test'
AUTH_DATABASE_URL_MIGRATIONS='postgresql://onetime_migrator:migratepass@127.0.0.1:2132/onetime_auth_test'
# The *_PG variants are what lib/tasks/spec.rake reads for its postgres
# tasks (it then sets the plain variables itself, to the same values).
AUTH_DATABASE_URL_PG='postgresql://onetime_user:testpass@127.0.0.1:2132/onetime_auth_test'
AUTH_DATABASE_URL_MIGRATIONS_PG='postgresql://onetime_migrator:migratepass@127.0.0.1:2132/onetime_auth_test'
EOF

write_file tests/lanes/full-pg/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake spec:integration:full:postgres
EOF

# ============================================================================
# Lane: full-pg-agnostic
# ============================================================================

write_file tests/lanes/full-pg-agnostic/env <<'EOF'
# Lane: full-pg-agnostic — DB-agnostic full-mode specs run against
# PostgreSQL (catches SQLite/PG behavior drift in specs that claim to be
# database-neutral).
# CI job: ruby-integration-full (T3, "PG agnostic" rows; billing via overlay)
#
# Same database env as full-pg; see that lane for where roles come from.
AUTHENTICATION_MODE=full
ORGS_SSO_ENABLED=true
AUTH_DATABASE_URL='postgresql://onetime_user:testpass@127.0.0.1:2132/onetime_auth_test'
AUTH_DATABASE_URL_MIGRATIONS='postgresql://onetime_migrator:migratepass@127.0.0.1:2132/onetime_auth_test'
AUTH_DATABASE_URL_PG='postgresql://onetime_user:testpass@127.0.0.1:2132/onetime_auth_test'
AUTH_DATABASE_URL_MIGRATIONS_PG='postgresql://onetime_migrator:migratepass@127.0.0.1:2132/onetime_auth_test'
EOF

write_file tests/lanes/full-pg-agnostic/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake spec:integration:full:agnostic_on_pg
EOF

# ============================================================================
# Lane: disabled
# ============================================================================

write_file tests/lanes/disabled/env <<'EOF'
# Lane: disabled — integration specs for AUTHENTICATION_MODE=disabled
# (auth code paths intentionally absent; see ADR-007).
# CI job: ruby-integration-disabled (T3)
AUTHENTICATION_MODE=disabled
EOF

write_file tests/lanes/disabled/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake spec:integration:disabled
EOF

# ============================================================================
# Lane: api
# ============================================================================

write_file tests/lanes/api/env <<'EOF'
# Lane: api — API contract specs (spec/api), an axis separate from auth
# mode. Needs only Valkey.
# CI: non-blocking step in ruby-integration-simple (T3) while #3225 is
# open. Gating policy (blocking or not) is CI's decision, not the lane's;
# the lane just defines the run.
AUTHENTICATION_MODE=simple
EOF

write_file tests/lanes/api/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
pnpm run locales:sync
bundle exec rake spec:api
EOF

# ============================================================================
# Lane: smoke
# ============================================================================

write_file tests/lanes/smoke/env <<'EOF'
# Lane: smoke — representative cross-stack check (target: under 2 min).
# Cleans the TEST valkey (2121), runs smoke:ruby, then vitest.
# CI job: smoke-test (T3)
AUTHENTICATION_MODE=simple
EOF

write_file tests/lanes/smoke/tasks <<'EOF'
# Lane tasks: executed top-to-bottom from the repo root by tests/lanes/run
# (bash -euo pipefail: first failure stops the lane). Keep each line standalone.
#
# smoke:ruby includes spec:apps:web_billing, which reads the gitignored
# generated billing schema — hence schemas:json:generate.
pnpm run locales:sync
pnpm run schemas:json:generate
pnpm run test:smoke
EOF

# ============================================================================
# Per-lane .envrc (identical body; direnv interactive convenience)
# ============================================================================

LANES=(unit simple full-sqlite full-pg full-pg-agnostic disabled api smoke)

# Process substitution (not a pipe): write_file must run in this shell so
# its created/skipped tracking survives.
for lane in "${LANES[@]}"; do
  write_file "tests/lanes/${lane}/.envrc" < <(
    echo "# tests/lanes/${lane}/.envrc — direnv hook for the '${lane}' lane."
    cat <<'EOF'
#
# Interactive convenience ONLY. CI and tests/lanes/run never read .envrc;
# they source base.env + env directly (and hermetically). cd here, run
# `direnv allow` once, and your shell carries this lane's environment —
# the same workflow as the per-environment infra config directories.
#
# Load order: ../base.env (via source_up) -> ./env -> optional overlays.
#
# Overlays: list names, one per line, in a gitignored `.overlays` file:
#   echo billing > .overlays && direnv reload
source_up
dotenv env
watch_file .overlays
if [ -f .overlays ]; then
  while IFS= read -r name; do
    [ -n "$name" ] && dotenv "../overlays/${name}.env"
  done < .overlays
fi
EOF
  )
done

# ============================================================================
# tests/lanes/README.md — the contract
# ============================================================================

write_file tests/lanes/README.md <<'EOF'
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
21. New services take "21 + last two digits of the canonical port";
valkey predates the scheme and keeps its established 2121. Dev services
keep canonical ports. A leaked dev config therefore cannot reach a test
service, and a test run cannot reach dev data. This plus the hermetic
runner is the answer to "tests wiped my dev database".

| Service  | Test port | Canonical                |
| -------- | --------- | ------------------------ |
| valkey   | 2121      | 6379 (port grandfathered)|
| postgres | 2132      | 5432                     |
| rabbitmq | 2172      | 5672                     |

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
EOF

# ============================================================================
# .gitignore — local-only direnv overlay markers
# ============================================================================

if ! grep -qF 'tests/lanes/**/.overlays' .gitignore 2>/dev/null; then
  {
    echo ''
    echo '# Local direnv overlay markers in test lanes (tests/lanes/README.md)'
    echo 'tests/lanes/**/.overlays'
  } >> .gitignore
  created+=('.gitignore (appended)')
fi

# The repo-wide "*.env / .env*" ignore rules are policy: env files don't
# get committed. tests/lanes/ is the deliberate exception — committed,
# secret-free, and the whole point of the tree — so re-include it.
if ! grep -qF '!tests/lanes/base.env' .gitignore 2>/dev/null; then
  {
    echo ''
    echo '# Test lanes are the exception to the env-file ignore rules above:'
    echo '# committed on purpose, dummy values only (tests/lanes/README.md)'
    echo '!tests/lanes/**/.envrc'
    echo '!tests/lanes/base.env'
    echo '!tests/lanes/overlays/*.env'
  } >> .gitignore
  created+=('.gitignore (lane re-include rules appended)')
fi

chmod +x tests/lanes/run

# ============================================================================
# Summary
# ============================================================================

echo
echo "Created:"
if [[ ${#created[@]} -gt 0 ]]; then
  printf '  %s\n' "${created[@]}"
else
  echo '  (nothing — everything already exists)'
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo
  echo "Skipped (already exist; --force to overwrite):"
  printf '  %s\n' "${skipped[@]}"
fi

echo
echo "Next steps:"
echo "  docker compose -f compose.test.yml up --wait -d"
echo "  tests/lanes/run --list"
echo "  tests/lanes/run unit"
