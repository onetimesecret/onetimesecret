#!/usr/bin/env bash

# install-test.sh
#
# Switches this checkout to test mode and makes the RSpec suite runnable on a
# fresh clone, with no maintainer-private files required.
#
# What it does (in order):
#   - Picks a datastore CLI/server: valkey-* if present, else redis-* (Valkey
#     is wire-compatible with Redis, and the test config talks plain redis://)
#   - Verifies the required toolchain (ruby, bundler, pnpm, a datastore)
#   - Warns if Ruby is older than the Gemfile floor (>= 3.4.7)
#   - Seeds etc/ config files from etc/defaults/ (mirrors CI)
#   - Installs Ruby gems and Node dependencies if they are missing
#   - Starts a throwaway test datastore on port 2121 (no persistence)
#   - Smoke-tests that config resolves to the test database
#
# Optional, only when the relevant tooling/config is present:
#   - direnv: generates .envrc + a .test-mode marker so `cd` into the checkout
#     loads .env.test automatically (handy for switching dev/test lanes)
#   - PostgreSQL: provisions the auth integration database when a superuser URL
#     is available (via AUTH_DATABASE_URL_TEST_SUPERUSER or .env.test)
#
# After this script, the unit/fast suites just work:
#   pnpm run test:rspec:fast      # RSpec
#   pnpm test                     # Vitest
#
# To switch back to dev mode (removes .test-mode), run install-dev.sh.
#
# Idempotent: safe to re-run at any time.

set -euo pipefail

# Sanity check
if [[ ! -f "Gemfile" ]]; then
    echo "Error: Run this from an OTS checkout root"
    exit 1
fi

# --- Datastore CLI/server: prefer Valkey, fall back to Redis ----------
#
# The test config (spec/config.test.yaml) connects to redis://127.0.0.1:2121,
# and Valkey speaks the Redis wire protocol, so redis-server/redis-cli are a
# drop-in substitute. Honor explicit VALKEY_SERVER/VALKEY_CLI overrides first;
# the package.json database scripts read the same two variables.

VALKEY_CLI="${VALKEY_CLI:-$(command -v valkey-cli   || command -v redis-cli    || true)}"
VALKEY_SERVER="${VALKEY_SERVER:-$(command -v valkey-server || command -v redis-server || true)}"
export VALKEY_CLI VALKEY_SERVER

# --- Required tools ---------------------------------------------------

missing_required=()
command -v ruby   &>/dev/null || missing_required+=("ruby    (>= 3.4.7):  https://www.ruby-lang.org/")
command -v bundle &>/dev/null || missing_required+=("bundler (gem install bundler)")
command -v pnpm   &>/dev/null || missing_required+=("pnpm    (Node package manager):  https://pnpm.io/installation")
if [[ -z "$VALKEY_CLI" || -z "$VALKEY_SERVER" ]]; then
    missing_required+=("valkey-server/valkey-cli (or redis-server/redis-cli):  https://valkey.io/download/")
fi
if (( ${#missing_required[@]} > 0 )); then
    echo "Error: Required tools missing:"
    for tool in "${missing_required[@]}"; do
        echo "  - $tool"
    done
    exit 1
fi

echo "OK:   datastore -> server '$VALKEY_SERVER', cli '$VALKEY_CLI'"

# --- Ruby version (soft check) ---------------------------------------
#
# The Gemfile pins `ruby '>= 3.4.7'`; bundler will refuse to run on anything
# older. Warn early with an actionable message instead of failing deep inside
# `bundle install`.

required_ruby="3.4.7"
current_ruby="$(ruby -e 'print RUBY_VERSION')"
if ! printf '%s\n%s\n' "$required_ruby" "$current_ruby" | sort -V -C; then
    echo "Warning: Ruby $current_ruby is older than the Gemfile floor ($required_ruby)."
    echo "  Install $required_ruby+ with rbenv/rvm/asdf and re-run, or gems will not install."
else
    echo "OK:   Ruby $current_ruby satisfies >= $required_ruby"
fi

# --- Config files from defaults (mirrors CI) -------------------------
#
# etc/defaults/*.defaults.<ext> are templates; the app reads etc/*.<ext>.
# Seed any that are missing so config resolves on a clean checkout.

echo "---"
echo "Seeding etc/ config from defaults..."
for file in etc/defaults/*.defaults.*; do
    [[ -f "$file" ]] || continue
    target="etc/$(basename "$file" | sed 's/\.defaults//')"
    if [[ -f "$target" ]]; then
        echo "OK:   $target exists"
    else
        cp "$file" "$target"
        echo "Copy: $target (from $(basename "$file"))"
    fi
done

# --- Dependencies -----------------------------------------------------

echo "---"
if bundle check &>/dev/null; then
    echo "OK:   Ruby gems already installed"
else
    echo "Installing Ruby gems (bundle install)..."
    bundle install
fi

if [[ -d node_modules ]]; then
    echo "OK:   node_modules present"
else
    echo "Installing Node dependencies (pnpm install)..."
    pnpm install
fi

# --- Generated locales ------------------------------------------------

echo "---"
echo "Generating merged locale files..."
# Delegate to the canonical pnpm entry point (python3 i18n content compile --all)
# so this stays in step with the project rather than re-spelling the CLI flags.
if pnpm run locales:sync; then
    echo "OK:   Locales generated in generated/locales/"
else
    echo "Warning: locale generation failed (pnpm run locales:sync) — continuing."
    echo "  Some i18n-dependent tests may fail until locales are generated."
fi

# --- Test datastore on port 2121 -------------------------------------

echo "---"
echo "Starting test datastore on port 2121..."

if "$VALKEY_CLI" -p 2121 ping &>/dev/null; then
    echo "OK:   Test datastore already running on port 2121"
else
    pnpm run test:database:start

    started=false
    for _i in 1 2 3 4 5 6 7 8 9 10; do
        if "$VALKEY_CLI" -p 2121 ping &>/dev/null; then
            started=true
            break
        fi
        sleep 0.5
    done

    if $started; then
        echo "OK:   Test datastore started on port 2121"
    else
        echo "Error: Test datastore did not start on port 2121"
        echo "  Try manually: pnpm run test:database:start:fg"
        exit 1
    fi
fi

# --- Optional: direnv lane switching ---------------------------------
#
# direnv is a convenience, not a requirement. The RSpec suite forces
# RACK_ENV=test in spec_helper and the test config hardcodes its values, so
# tests run fine without it. When direnv IS installed we wire up the
# .envrc/.test-mode flow so `cd` into the checkout selects the test lane.

echo "---"
if command -v direnv &>/dev/null; then
    if [[ ! -f ".envrc" ]]; then
        echo "Creating .envrc (direnv detected)..."
        cat > ".envrc" << 'ENVRC'
# .envrc — generated by install-test.sh
#
# direnv loads this automatically when you cd into the checkout.
# Mode is controlled by the .test-mode file:
#   install-test.sh  creates it  → test mode
#   install-dev.sh   removes it  → dev mode

source_up_if_exists

watch_file .test-mode

if [ -f .test-mode ]; then
  export OTS_ENV_LOADED=test
  dotenv_if_exists .env.test
else
  export OTS_ENV_LOADED=dev
  dotenv_if_exists

  # .env.local overrides happen last if the file exists. And only in dev mode.
  #
  # Because each dotenv call just exports variables into the same sub-shell, the order
  # you write them determines precedence — later calls override earlier ones. So
  # .env.local values would win over .env values in the above setup.
  #
  test -f .env.local && dotenv .env.local
fi
ENVRC
        echo "Created: .envrc"
    else
        echo "OK:   .envrc already exists"
    fi

    echo "Activating test mode (.test-mode)..."
    touch .test-mode
    direnv allow .
else
    echo "Skip: direnv not installed — the test suite runs fine without it"
    echo "      (spec_helper forces RACK_ENV=test and the test config is self-contained)."
    echo ""
    echo "Recommended: install direnv to manage environment variables for everyday"
    echo "  development. It auto-loads .env when you cd into the checkout (dev mode)"
    echo "  and is the intended way to run the app, the console, and bin/ots:"
    echo "    - dev setup:  ./install-dev.sh"
    echo "    - dev server: bin/dev   (or bundle exec puma -C etc/puma.rb)"
    echo "    - console:    bin/console"
    echo "    - CLI:        bin/ots <command>"
    echo "  Install direnv: https://direnv.net/docs/installation.html"
fi

# --- Optional: .env.test for integration tests -----------------------
#
# Only the PostgreSQL-backed integration tests need extra config. Seed a
# starting point from the committed .env.test.example when nothing is present.

OTS_DEV_CONFIG="${OTS_DEV_CONFIG:-$HOME/.config/onetimesecret-dev}"

if [[ -f ".env.test" ]]; then
    echo "OK:   .env.test exists"
elif [[ -f "$OTS_DEV_CONFIG/.env.test" ]]; then
    ln -snf "$OTS_DEV_CONFIG/.env.test" .env.test
    echo "Link: .env.test -> $OTS_DEV_CONFIG/.env.test"
elif [[ -f ".env.test.example" ]]; then
    cp ".env.test.example" ".env.test"
    echo "Copy: .env.test (from .env.test.example — fill in for integration tests)"
fi

# --- Optional: PostgreSQL integration database -----------------------

pg_superuser_url="${AUTH_DATABASE_URL_TEST_SUPERUSER:-}"
if [[ -z "$pg_superuser_url" && -f ".env.test" ]]; then
    # Fall back to .env.test if direnv hasn't loaded yet
    pg_superuser_url=$(grep '^AUTH_DATABASE_URL_TEST_SUPERUSER=' .env.test 2>/dev/null | cut -d= -f2- || true)
fi

echo "---"
if [[ -n "$pg_superuser_url" ]] && command -v psql &>/dev/null; then
    echo "Provisioning PostgreSQL test database (integration tests)..."

    # Extract the database name from the superuser URL.
    # Parse: postgresql://user[:pass]@host[:port]/dbname[?query]
    # (URI parsing so query params like ?sslmode=require don't leak into the name)
    pg_db=$(ruby -ruri -e 'puts URI(ARGV.fetch(0)).path.sub(%r{\A/}, "")' "$pg_superuser_url")

    # Create the database if it doesn't exist (createdb is idempotent-ish)
    if psql "$pg_superuser_url" -c "SELECT 1" &>/dev/null; then
        echo "OK:   Database '$pg_db' exists"
    else
        # Connect to 'postgres' maintenance DB to create the test DB
        # (URI parsing so query params like ?sslmode=require are preserved)
        pg_maintenance_url=$(ruby -ruri -e 'uri = URI(ARGV.fetch(0)); uri.path = "/postgres"; puts uri.to_s' "$pg_superuser_url")
        createdb_output=$(psql "$pg_maintenance_url" -c "CREATE DATABASE \"$pg_db\"" 2>&1) || {
            if echo "$createdb_output" | grep -q "already exists"; then
                echo "OK:   Database '$pg_db' already exists"
            else
                echo "Error: Failed to create database '$pg_db': $createdb_output"
                exit 1
            fi
        }
        echo "OK:   Created database '$pg_db'"
    fi

    # Run the shared provisioning script (roles, grants, schema reset)
    psql "$pg_superuser_url" -f apps/web/auth/migrations/schemas/postgres/initialize_test_db.sql -v ON_ERROR_STOP=1
    echo "OK:   PostgreSQL roles and grants provisioned"
else
    echo "Skip: PostgreSQL setup (only needed for integration tests)."
    echo "  Set AUTH_DATABASE_URL_TEST_SUPERUSER (or add it to .env.test) and install psql to enable."
fi

# --- Smoke test ------------------------------------------------------

echo "---"
echo "Verifying test environment config..."

smoke_ruby='
  ENV["RACK_ENV"] = "test"
  require_relative "lib/onetime"
  OT::Config.before_load
  raw  = OT::Config.load
  conf = OT::Config.after_load(raw)
  puts conf.dig("redis", "uri")
'

if command -v direnv &>/dev/null && [[ -f ".test-mode" ]]; then
    test_uri=$(direnv exec . ruby -e "$smoke_ruby" || true)
else
    test_uri=$(env RACK_ENV=test ruby -e "$smoke_ruby" || true)
fi

if [[ "$test_uri" == *":2121"* ]]; then
    echo "OK:   Config resolves to test database ($test_uri)"
else
    echo "Warning: Config did not resolve to port 2121 (got: ${test_uri:-<empty>})"
    echo "  spec/config.test.yaml should hardcode redis://127.0.0.1:2121/0"
    echo "  Verify RACK_ENV=test is set and ConfigResolver finds the test config"
fi

# --- Done ------------------------------------------------------------

echo "---"
echo "Test environment ready."
echo "  RSpec:  pnpm run test:rspec:fast"
echo "  Vitest: pnpm test"
echo "  Switch back to dev mode: install-dev.sh"
