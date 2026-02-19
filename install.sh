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
  [[ -z "$required" ]] && return 0

  has "$cmd" || die "$name not found (need $required)"

  actual=$($extractor)
  [[ "$actual" == "$required" ]] || die "$name version mismatch: have $actual, need $required"

  info "$name $actual"
}

check_version_major() {
  local name="$1" cmd="$2" file="$3" extractor="$4"
  local required actual

  required=$(version_from "$file" | cut -d. -f1 | sed 's/^v//')
  [[ -z "$required" ]] && return 0

  has "$cmd" || die "$name not found (need $required+)"

  actual=$($extractor | sed 's/^v//' | cut -d. -f1)
  [[ "$actual" -ge "$required" ]] || die "$name too old: have $actual, need $required+"

  info "$name $($extractor)"
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

  for pkg in "pnpm-lock.yaml:pnpm:" "package-lock.json:npm:ci" "yarn.lock:yarn:--frozen-lockfile"; do
    IFS=: read -r lockfile mgr flags <<< "$pkg"
    if [[ -f "$lockfile" ]]; then
      info "Installing node packages ($mgr)..."
      $mgr install $flags
      return
    fi
  done

  [[ -f package.json ]] && warn "No lockfile, skipping node packages"
}

auth_mode() {
  # Read from env or .env file, defaulting to simple
  local mode="${AUTHENTICATION_MODE:-}"
  if [[ -z "$mode" && -f .env ]]; then
    mode=$(grep -E '^AUTHENTICATION_MODE=' .env 2>/dev/null | cut -d= -f2 | trim || echo "")
  fi
  echo "${mode:-simple}"
}

cmd_init() {
  info "Initializing..."

  check_version "Ruby" ruby .ruby-version 'ruby -e "puts RUBY_VERSION"'
  check_version_major "Node" node .nvmrc 'node -v'

  install_gems
  install_node

  info "Running rake ots:secrets..."
  bundle exec rake ots:secrets

  local mode
  mode=$(auth_mode)

  if [[ "$mode" == "full" ]]; then
    warn ""
    warn "AUTHENTICATION_MODE=full detected. Additional setup may be required:"
    warn ""
    warn "  RabbitMQ (if using background jobs):"
    warn "    bin/ots queue init"
    warn ""
    warn "  PostgreSQL (if using PostgreSQL as auth database):"
    warn "    Run apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql"
    warn "    as a PostgreSQL superuser before first boot."
    warn "    (Not required for SQLite.)"
    warn ""
  fi

  info "Done"
}

cmd_console() {
  exec bundle exec irb -r ./lib/onetime
}

cmd_doctor() {
  info "Checking environment..."

  (check_version "Ruby" ruby .ruby-version 'ruby -e "puts RUBY_VERSION"') || true
  (check_version_major "Node" node .nvmrc 'node -v') || true

  if has redis-cli && redis-cli ping &>/dev/null; then
    info "Redis responding"
  else
    warn "Redis not responding or not found"
  fi

  [[ -f .env ]] && info ".env exists" || warn ".env missing"

  local mode
  mode=$(auth_mode)
  info "AUTHENTICATION_MODE: $mode"

  if [[ "$mode" == "full" ]]; then
    if has psql; then
      info "psql found"
    else
      warn "psql not found (required for full auth mode with PostgreSQL)"
    fi
  fi
}

cmd_help() {
  cat <<EOF
Usage: install.sh <command>

Commands:
  init      Install dependencies, generate secrets, prepare environment
  console   Interactive Ruby console with app loaded
  doctor    Check environment for common issues
  help      Show this message
EOF
}

case "${1:-help}" in
  init)             cmd_init ;;
  console)          cmd_console ;;
  doctor)           cmd_doctor ;;
  help|-h|--help)   cmd_help ;;
  *)                die "Unknown command: $1" ;;
esac
