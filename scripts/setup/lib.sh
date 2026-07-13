# shellcheck shell=bash
# scripts/setup/lib.sh
#
# Shared spine for bin/setup. Sourced, not executed. Callers run under
# `set -euo pipefail`.
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

# --- Generic connectivity probes (doctor v2, BM-05) ---------------------
#
# Service availability is decided by CONNECTIVITY, never by whether a client
# CLI happens to be installed locally — remote/containerized services must
# read as up (BM-05).

# tcp_probe HOST PORT [TIMEOUT] — plain TCP connect via /dev/tcp.
# `timeout` guards against filtered hosts that hang the connect; when the
# binary is absent (stock macOS) we connect directly — localhost probes,
# the common case, fail fast anyway.
tcp_probe() {
  local host="$1" port="$2" t="${3:-5}"
  if has timeout; then
    timeout "$t" bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$host" "$port" 2>/dev/null
  else
    ( exec 3<>"/dev/tcp/$host/$port" ) 2>/dev/null
  fi
}

# url_host_port URL DEFAULT_PORT — strip scheme/userinfo/path, print "host port".
url_host_port() {
  local url="$1" default_port="$2" clean host port
  clean="${url#*://}"
  [[ "$clean" == *@* ]] && clean="${clean#*@}"
  clean="${clean%%/*}"
  clean="${clean%%\?*}"
  host="${clean%%:*}"
  if [[ "$clean" == *:* ]]; then
    port="${clean#*:}"
  else
    port=""
  fi
  echo "${host:-127.0.0.1}" "${port:-$default_port}"
}

# dotenv_get VAR — value of VAR from .env (first match wins, like install.sh's
# historical sed), empty when absent. Comments and quotes stripped.
dotenv_get() {
  [[ -f .env ]] || return 0
  sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*[\"']?([^\"'#[:space:]]*)[\"']?[[:space:]]*(#.*)?$/\1/p" .env 2>/dev/null | head -1
}

# env_or_dotenv VAR — process environment wins, .env is the fallback.
env_or_dotenv() {
  local name="$1" val
  val="${!name:-}"
  [[ -z "$val" ]] && val="$(dotenv_get "$name")"
  echo "$val"
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
  url_host_port "$(redis_url)" 6379
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

# Installs are FROZEN whenever a committed lockfile exists: setup must never
# rewrite Gemfile.lock / pnpm-lock.yaml (the fresh-clone CI lane fails on any
# tracked-file drift, lockfiles included). Updating a lockfile is a deliberate
# act — run the package manager directly, commit the result.

install_gems() {
  has bundle || gem install bundler

  if bundle check &>/dev/null; then
    echo "OK:   Ruby gems already installed"
    return 0
  fi

  if [[ -f Gemfile.lock ]]; then
    info "Installing Ruby gems (bundle install, frozen lockfile)..."
    BUNDLE_FROZEN=true bundle install --retry 3 ||
      die "bundle install failed in frozen mode. If you changed the Gemfile, run 'bundle install' yourself to update Gemfile.lock, commit it, then re-run bin/setup."
  else
    info "Fresh clone, generating lockfile (bundle install)..."
    bundle install --retry 3
    warn "Generated Gemfile.lock - consider committing"
  fi
}

install_node() {
  if [[ ! -f package.json ]]; then
    warn "No package.json — skipping node packages"
    return 0
  fi
  has pnpm || die "pnpm not found — install it first: https://pnpm.io/installation"
  if [[ -f pnpm-lock.yaml ]]; then
    info "Installing Node dependencies (pnpm install --frozen-lockfile)..."
    pnpm install --frozen-lockfile ||
      die "pnpm install failed with a frozen lockfile. If you changed package.json, run 'pnpm install' yourself to update pnpm-lock.yaml, commit it, then re-run bin/setup."
  else
    info "Installing Node dependencies (pnpm install)..."
    pnpm install
  fi
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
# (dev) removes it.
#
# The file carries a rev stamp (`# ots-envrc-rev: N`). Bump ENVRC_REV
# whenever the template below changes: generate_envrc regenerates stale
# files (backing up the old one to .envrc.bak) and `bin/setup --doctor`
# flags a mismatch. A rev-current file is left alone so local
# customisations survive re-runs.

ENVRC_REV=2

# envrc_rev_of FILE — the rev stamp of an .envrc, empty if unstamped.
envrc_rev_of() {
  sed -n 's/^# ots-envrc-rev: *//p' "${1:-.envrc}" 2>/dev/null | head -1
}

generate_envrc() {
  if [[ -f ".envrc" ]]; then
    if [[ "$(envrc_rev_of .envrc)" == "$ENVRC_REV" ]]; then
      echo "OK:   .envrc current (rev $ENVRC_REV)"
      return 0
    fi
    mv ".envrc" ".envrc.bak"
    echo "Note: .envrc was stale (older rev or pre-rev) — regenerating."
    echo "      Previous file kept at .envrc.bak; re-apply any local customisations."
  else
    echo "Creating .envrc..."
  fi

  # Unquoted heredoc so ENVRC_REV expands — keep the body free of other $/backticks.
  cat > ".envrc" << ENVRC
# .envrc — generated by bin/setup
# ots-envrc-rev: ${ENVRC_REV}
#
# direnv loads this automatically when you cd into the checkout.
# Mode is controlled by the .test-mode file:
#   bin/setup --test  creates it  → test mode
#   bin/setup         removes it  → dev mode

source_up_if_exists

# Explicit watch list: dotenv_if_exists also watches, but only the files the
# active branch touches. Watching all of them (existing or not) means edits —
# including through the .env symlink — and file creation both trigger a reload.
watch_file .test-mode .env .env.local .env.test

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
  dotenv_if_exists .env.local
fi
ENVRC
  echo "Created: .envrc (rev $ENVRC_REV)"
}

# --- Misc shared state --------------------------------------------------

auth_mode() {
  # Read from env or .env file, defaulting to simple
  local mode
  mode="$(env_or_dotenv AUTHENTICATION_MODE)"
  echo "${mode:-simple}"
}

is_initialized() {
  bundle exec bin/ots install check 2>/dev/null
}

require_checkout_root() {
  [[ -f "Gemfile" ]] || die "Run this from an OTS checkout root"
}
