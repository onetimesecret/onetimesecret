# shellcheck shell=bash
# scripts/setup/lib.sh
#
# Shared spine for bin/setup (and, during the deprecation window, the
# install.sh / install-dev.sh / install-test.sh delegates). Sourced, not
# executed. Callers run under `set -euo pipefail`.
#
# Bash 3.2 compatible on purpose: macOS ships 3.2, and the old
# install-dev.sh hard-failed there over a single associative array (DX-15).
# No `declare -A`, no `${var,,}`, no readarray in this file.

# --- Output helpers ----------------------------------------------------

has()    { command -v "$1" &>/dev/null; }
red()    { [[ -t 1 ]] && echo -e "\033[0;31m$1\033[0m" || echo "$1"; }
green()  { [[ -t 1 ]] && echo -e "\033[0;32m$1\033[0m" || echo "$1"; }
yellow() { [[ -t 1 ]] && echo -e "\033[0;33m$1\033[0m" || echo "$1"; }
info()   { green "▶ $1"; }
warn()   { yellow "▶ $1"; }
err()    { red "▶ $1" >&2; }
die()    { err "$1"; exit 1; }
trim()   { tr -d '[:space:]'; }

# --- Version gates -----------------------------------------------------

version_from() { [[ -f "$1" ]] && trim < "$1" || echo ""; }

# Exact-match: bundler enforces the exact version in .ruby-version
# (Gemfile: `ruby file: '.ruby-version'`), so the early gate must agree —
# a floor-compare would pass 3.4.10 only for bundler to reject it. (NF-5)
check_version_exact() {
  local name="$1" cmd="$2" file="$3" extractor="$4"
  local required actual

  required=$(version_from "$file")
  if [[ -z "$required" ]]; then
    has "$cmd" || die "$name not found ($(basename "$file") missing — cannot determine required version)"
    local detected
    detected=$(eval "$extractor")
    warn "$name $detected detected but no $(basename "$file") to pin against — version not verified"
    return 0
  fi

  has "$cmd" || die "$name not found (need exactly $required — see $(basename "$file"))"

  actual=$(eval "$extractor")
  if [[ "$actual" != "$required" ]]; then
    die "$name version mismatch: have $actual, need exactly $required ($(basename "$file"); bundler enforces the same). Install it with e.g. 'rbenv install $required' or 'mise use ruby@$required'."
  fi

  info "$name $actual"
}

check_version_major() {
  local name="$1" cmd="$2" file="$3" extractor="$4"
  local required actual_full actual

  required=$(version_from "$file" | sed 's/^v//' | cut -d. -f1)
  if [[ -z "$required" ]]; then
    has "$cmd" || die "$name not found ($(basename "$file") missing — cannot determine required version)"
    local detected
    detected=$(eval "$extractor" | sed 's/^v//')
    warn "$name $detected detected but no $(basename "$file") to pin against — version not verified"
    return 0
  fi

  has "$cmd" || die "$name not found (need $required+)"

  actual_full=$(eval "$extractor" | sed 's/^v//')
  actual=$(echo "$actual_full" | cut -d. -f1)
  [[ "$actual" -ge "$required" ]] || die "$name too old: have $actual, need $required+"

  info "$name $actual_full"
}

# --- Datastore discovery and probes ------------------------------------
#
# The app and the test config speak plain redis://, and Valkey is
# wire-compatible, so valkey-* and redis-* binaries are interchangeable.
# Honor explicit VALKEY_SERVER/VALKEY_CLI overrides first; the package.json
# database scripts read the same two variables.

datastore_discover() {
  VALKEY_CLI="${VALKEY_CLI:-$(command -v valkey-cli    || command -v redis-cli    || true)}"
  VALKEY_SERVER="${VALKEY_SERVER:-$(command -v valkey-server || command -v redis-server || true)}"
  export VALKEY_CLI VALKEY_SERVER
}

redis_url() {
  # Resolve VALKEY_URL -> REDIS_URL -> .env -> default (matches entrypoint.sh)
  local url="${VALKEY_URL:-${REDIS_URL:-}}"
  if [[ -z "$url" && -f .env ]]; then
    url=$(sed -n -E "s/^[[:space:]]*(VALKEY_URL|REDIS_URL)[[:space:]]*=[[:space:]]*[\"']?([^\"'#[:space:]]*)[\"']?[[:space:]]*(#.*)?$/\2/p" .env 2>/dev/null | head -1)
  fi
  echo "${url:-redis://127.0.0.1:6379}"
}

redis_host_port() {
  local url clean host port
  url=$(redis_url)
  clean="${url#redis://}"
  clean="${clean#valkey://}"
  if [[ "$clean" == *@* ]]; then
    clean="${clean#*@}"
  fi
  host="${clean%%:*}"
  port="${clean#*:}"
  port="${port%%/*}"
  echo "${host:-127.0.0.1}" "${port:-6379}"
}

redis_reachable() {
  local rhost rport
  read -r rhost rport < <(redis_host_port)
  if has valkey-cli && valkey-cli -h "$rhost" -p "$rport" ping &>/dev/null; then return 0; fi
  if has redis-cli  && redis-cli  -h "$rhost" -p "$rport" ping &>/dev/null; then return 0; fi
  # CLI-free fallback: plain TCP connect (confirms the port is open)
  (exec 3<>"/dev/tcp/$rhost/$rport") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}

# --- Config seeding -----------------------------------------------------
#
# etc/defaults/*.defaults.<ext> are templates; the app reads etc/*.<ext>.
# Seed any that are missing so config resolves on a clean checkout. Skips
# anything already present — including symlinks into OTS_DEV_CONFIG, which
# the dev lane creates before calling this.

seed_configs() {
  local file target
  for file in etc/defaults/*.defaults.*; do
    [[ -f "$file" ]] || continue
    target="etc/$(basename "$file" | sed 's/\.defaults//')"
    if [[ -e "$target" || -L "$target" ]]; then
      echo "OK:   $target exists"
    else
      cp "$file" "$target"
      echo "Copy: $target (from $(basename "$file"))"
    fi
  done

  # Puma config comes from etc/examples/, not etc/defaults/
  if [[ ! -e "etc/puma.rb" && -f "etc/examples/puma.example.rb" ]]; then
    [[ -L "etc/puma.rb" ]] && rm "etc/puma.rb"
    cp etc/examples/puma.example.rb etc/puma.rb
    echo "Copy: etc/puma.rb (from etc/examples/puma.example.rb)"
  fi
}

# --- Dependencies -------------------------------------------------------

install_gems() {
  has bundle || gem install bundler

  if bundle check &>/dev/null; then
    echo "OK:   Ruby gems already installed"
    return 0
  fi

  local fresh
  fresh=$([[ -f Gemfile.lock ]] && echo false || echo true)
  $fresh && info "Fresh clone, generating lockfile..."

  info "Installing Ruby gems (bundle install)..."
  bundle install --retry 3

  $fresh && warn "Generated Gemfile.lock - consider committing" || true
}

install_node() {
  if [[ ! -f package.json ]]; then
    warn "No package.json — skipping node packages"
    return 0
  fi
  has pnpm || die "pnpm not found — install it first: https://pnpm.io/installation"
  info "Installing Node dependencies (pnpm install)..."
  pnpm install
}

# --- Generated artifacts ------------------------------------------------
#
# Schemas and locales are backend inputs, not frontend build output: the
# Ruby side reads generated/schemas/**/*.schema.json and the compiled locale
# JSON at runtime, and the RSpec fast suite asserts on the schemas (TR-01).
# They are normally a side-effect of `pnpm run build`, which setup
# deliberately never runs, so generate them explicitly.

generate_artifacts() {
  echo "Generating merged locale files (pnpm run locales:sync)..."
  if pnpm run locales:sync; then
    echo "OK:   Locales generated in generated/locales/"
  else
    warn "Locale generation failed (pnpm run locales:sync) — continuing."
    warn "  It needs python3; some i18n-dependent code and tests will fail until it succeeds."
  fi

  echo "Generating JSON schemas (pnpm run schemas:json:generate)..."
  if pnpm run schemas:json:generate; then
    echo "OK:   JSON schemas generated"
  else
    warn "Schema generation failed (pnpm run schemas:json:generate) — some specs may fail."
  fi
}

# --- Secrets ------------------------------------------------------------

ensure_secrets() {
  if grep -qE '^SECRET=.+' .env 2>/dev/null && ! grep -qE '^SECRET=CHANGEME' .env 2>/dev/null; then
    echo "OK:   SECRET already set in .env"
  else
    echo "SECRET is empty or CHANGEME — generating secrets (rake ots:secrets)..."
    bundle exec rake ots:secrets || warn "rake ots:secrets failed — set SECRET manually in .env"
  fi
}

# --- direnv / .envrc ----------------------------------------------------
#
# One canonical .envrc, shared by every lane. Mode is controlled by the
# .test-mode marker file: `bin/setup --test` creates it, `bin/setup`
# (dev) removes it. Creates the file if missing; leaves it alone if present
# so local customisations survive re-runs.

generate_envrc() {
  if [[ -f ".envrc" ]]; then
    echo "OK:   .envrc already exists"
    return 0
  fi

  echo "Creating .envrc..."
  cat > ".envrc" << 'ENVRC'
# .envrc — generated by bin/setup
#
# direnv loads this automatically when you cd into the checkout.
# Mode is controlled by the .test-mode file:
#   bin/setup --test  creates it  → test mode
#   bin/setup         removes it  → dev mode

source_up_if_exists

watch_file .test-mode

if [ -f .test-mode ]; then
  export OTS_ENV_LOADED=test
  echo "direnv: TEST MODE (.test-mode) active - RACK_ENV=test. Exit: bin/setup" >&2
  dotenv_if_exists .env.test
else
  export OTS_ENV_LOADED=dev
  export RACK_ENV=development
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
}

# --- Misc shared state --------------------------------------------------

auth_mode() {
  # Read from env or .env file, defaulting to simple
  local mode="${AUTHENTICATION_MODE:-}"
  if [[ -z "$mode" && -f .env ]]; then
    mode=$(sed -n -E "s/^[[:space:]]*AUTHENTICATION_MODE[[:space:]]*=[[:space:]]*[\"']?([^\"'#[:space:]]*)[\"']?[[:space:]]*(#.*)?$/\1/p" .env 2>/dev/null | head -1)
  fi
  echo "${mode:-simple}"
}

is_initialized() {
  bundle exec bin/ots install check 2>/dev/null
}

require_checkout_root() {
  [[ -f "Gemfile" ]] || die "Run this from an OTS checkout root"
}
