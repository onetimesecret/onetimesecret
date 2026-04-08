#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# Core utilities
has()      { command -v "$1" &>/dev/null; }
red()      { [[ -t 1 ]] && echo -e "\033[0;31m$1\033[0m" || echo "$1"; }
green()    { [[ -t 1 ]] && echo -e "\033[0;32m$1\033[0m" || echo "$1"; }
yellow()   { [[ -t 1 ]] && echo -e "\033[0;33m$1\033[0m" || echo "$1"; }
info()     { green "▶ $1"; }
warn()     { yellow "▶ $1"; }
err()      { red "▶ $1" >&2; }
die()      { err "$1"; exit 1; }
trim()     { tr -d '[:space:]'; }

# Version file reader
version_from() { [[ -f "$1" ]] && trim < "$1" || echo ""; }

check_version() {
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

  has "$cmd" || die "$name not found (need $required)"

  actual=$(eval "$extractor")
  [[ "$actual" == "$required" ]] || die "$name version mismatch: have $actual, need $required"

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

install_gems() {
  has bundle || gem install bundler

  local fresh=$([[ -f Gemfile.lock ]] && echo false || echo true)
  $fresh && info "Fresh clone, generating lockfile..."

  info "Installing gems..."
  bundle install --retry 3

  $fresh && warn "Generated Gemfile.lock - consider committing"
}

install_node() {
  local pkg mgr flags

  for pkg in "pnpm-lock.yaml:pnpm:install --frozen-lockfile" "package-lock.json:npm:ci" "yarn.lock:yarn:install --frozen-lockfile"; do
    IFS=: read -r lockfile mgr flags <<< "$pkg"
    if [[ -f "$lockfile" ]]; then
      has "$mgr" || die "$mgr not found but $lockfile exists — install $mgr first (see https://docs.onetimesecret.com/en/self-hosting/installation/)"
      info "Installing node packages ($mgr)..."
      $mgr $flags
      return
    fi
  done

  [[ -f package.json ]] && warn "No lockfile, skipping node packages"
}

is_initialized() {
  bundle exec bin/ots install check 2>/dev/null
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

auth_mode() {
  # Read from env or .env file, defaulting to simple
  local mode="${AUTHENTICATION_MODE:-}"
  if [[ -z "$mode" && -f .env ]]; then
    mode=$(sed -n -E "s/^[[:space:]]*AUTHENTICATION_MODE[[:space:]]*=[[:space:]]*[\"']?([^\"'#[:space:]]*)[\"']?[[:space:]]*(#.*)?$/\1/p" .env 2>/dev/null | head -1)
  fi
  echo "${mode:-simple}"
}

cmd_reconcile() {
  info "Reconciling environment..."

  install_gems
  install_node

  # Verify .env and SECRET exist before attempting derive
  if [[ ! -f .env ]]; then
    die ".env not found — run './install.sh init' first"
  fi
  if ! grep -qE '^SECRET=.+' .env 2>/dev/null; then
    die "SECRET is empty in .env — run './install.sh init' first to generate secrets"
  fi

  info "Re-deriving child keys from existing SECRET..."
  DERIVE=1 bundle exec rake ots:secrets || die "Failed to generate secrets"
  chmod 600 "${ENV_FILE:-.env}" || die "Failed to secure ${ENV_FILE:-.env} file permissions"

  local mode
  mode=$(auth_mode)

  if [[ "$mode" == "full" ]]; then
    info "Re-applying RabbitMQ policies and queue declarations..."
    bin/ots queue init --force
  fi

  info "Done"
}

cmd_init() {
  info "Initializing..."

  check_version "Ruby" ruby .ruby-version 'ruby -e "puts RUBY_VERSION"'
  check_version_major "Node" node .nvmrc 'node -v'

  # Install dependencies first — bundle exec is needed for subsequent steps
  install_gems
  install_node

  bundle exec rake ots:env:setup

  local mode
  mode=$(auth_mode)

  if [[ "$mode" == "full" ]]; then
    echo ""
    warn "AUTHENTICATION_MODE=full detected. Additional manual setup required before first boot:"
    echo ""
    warn "  PostgreSQL (if using PostgreSQL as auth database):"
    warn "    Run psql -U postgres -f apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql"
    warn "    as a PostgreSQL superuser."
    warn "    (Not required for SQLite.)"
    echo ""
  fi

  info "Generating secrets..."
  bundle exec rake ots:secrets || die "Failed to generate secrets"
  chmod 600 "${ENV_FILE:-.env}" || die "Failed to secure ${ENV_FILE:-.env} file permissions"

  if [[ "$mode" == "full" ]]; then
    info "Re-applying RabbitMQ policies and queue declarations..."
    bin/ots queue init --force
  fi

  # Check Redis/Valkey availability before attempting install mark
  redis_available=false
  read -r rhost rport < <(redis_host_port)
  if (has valkey-cli && valkey-cli -h "$rhost" -p "$rport" ping &>/dev/null) || \
     (has redis-cli && redis-cli -h "$rhost" -p "$rport" ping &>/dev/null); then
    redis_available=true
  fi

  if [[ "$redis_available" == true ]]; then
    if bundle exec bin/ots install mark; then
      info "Environment initialized (onetime:install:init_count incremented)"
    else
      warn "install mark failed (exit $?) — see errors above"
    fi
  else
    warn "Redis/Valkey not running — skipping install mark (run install.sh again after starting Valkey)"
  fi

  # Ensure puma config exists for the instructions below
  if [[ ! -e "etc/puma.rb" && -f "etc/examples/puma.example.rb" ]]; then
    [[ -L "etc/puma.rb" ]] && rm "etc/puma.rb"
    cp etc/examples/puma.example.rb etc/puma.rb
    info "Copied etc/examples/puma.example.rb -> etc/puma.rb"
  fi

  echo ""
  info "Next steps:"
  if [[ "$mode" == "full" ]]; then
    info "  1. Start Valkey/Redis and RabbitMQ"
    info "  2. Source environment:  source .env.sh"
    info "  3. Start the app:      bundle exec puma -C etc/puma.rb"
    info "  4. Start workers:      bundle exec bin/ots worker"
    info "  5. Start scheduler:    bundle exec bin/ots scheduler"
  else
    info "  1. Start Valkey/Redis"
    info "  2. Source environment:  source .env.sh"
    info "  3. Start the app:      bundle exec puma -C etc/puma.rb"
  fi
  echo ""
  warn "  With a Procfile runner:         foreman start -f Procfile.production"
  warn "  For development with Overmind:  bin/dev"
  warn "  Check environment health:       install.sh doctor"

  echo ""
  cmd_doctor || true
}

cmd_console() {
  exec bundle exec irb -r "./lib/onetime"
}

cmd_doctor() {
  info "Checking environment..."

  (check_version "Ruby" ruby .ruby-version 'ruby -e "puts RUBY_VERSION"') || true
  (check_version_major "Node" node .nvmrc 'node -v') || true

  read -r rhost rport < <(redis_host_port)
  if has valkey-cli && valkey-cli -h "$rhost" -p "$rport" ping &>/dev/null; then
    info "Valkey responding ($rhost:$rport)"
  elif has redis-cli && redis-cli -h "$rhost" -p "$rport" ping &>/dev/null; then
    info "Redis responding ($rhost:$rport)"
  else
    warn "Valkey/Redis not responding at $rhost:$rport"
  fi

  if has overmind; then
    info "Overmind found (for development use: bin/dev)"
  else
    warn "Overmind not found — needed for bin/dev (install: https://github.com/DarthSim/overmind)"
  fi

  [[ -f .env ]] && info ".env exists" || warn ".env missing"
  [[ -f etc/puma.rb ]] && info "etc/puma.rb exists" || warn "etc/puma.rb missing (copy from etc/examples/puma.example.rb)"
  [[ -f Procfile.dev ]] && info "Procfile.dev exists" || warn "Procfile.dev missing (copy from Procfile.dev.example)"

  local mode
  mode=$(auth_mode)
  info "AUTHENTICATION_MODE: $mode"

  if [[ "$mode" == "full" ]]; then
    if has psql; then
      info "psql found"
    else
      warn "psql not found (required for full auth mode with PostgreSQL)"
    fi

    if has rabbitmqctl; then
      info "rabbitmqctl found"
    else
      warn "rabbitmqctl not found (required for background jobs in full auth mode)"
    fi
  fi
}

cmd_help() {
  cat <<EOF
Usage: install.sh [command]

With no command, auto-detects: init for new environments, reconcile for existing ones.

Commands:
  init        Install dependencies, generate secrets, prepare environment
  reconcile   Re-derive child keys and re-apply RabbitMQ policies (idempotent)
  console     Interactive Ruby console with app loaded
  doctor      Check environment for common issues
  help        Show this message
EOF
}

case "${1:-auto}" in
  auto)
    if is_initialized; then
      info "Existing environment detected — running reconcile"
      cmd_reconcile
    else
      info "Environment not initialized — running init"
      cmd_init
    fi
    ;;
  init)             cmd_init ;;
  reconcile)        cmd_reconcile ;;
  console)          cmd_console ;;
  doctor)           cmd_doctor ;;
  help|-h|--help)   cmd_help ;;
  *)                cmd_help >&2; die "Unknown command: $1" ;;
esac
