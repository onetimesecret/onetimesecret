#!/bin/bash

# scripts/check-migration-status.sh

##
# MIGRATION STATUS CHECK SCRIPT
#
# Checks if migrations are needed by delegating to the migration
# scripts themselves (single source of truth). Runs migrations in
# order, so users who skip releases still get all previous migrations.
#
# Usage:
#   ./check-migration-status.sh
#
# Environment:
#   CONFIG_MIGRATE=check (default) - Check and halt if migration needed
#   CONFIG_MIGRATE=auto            - Automatically run migrations
#   CONFIG_MIGRATE=skip            - Skip migration check entirely
#
# Exit codes:
#   0 - All migrations applied or not needed
#   1 - Migration needed (check mode) or migration failed
#

set -e

CONFIG_MIGRATE="${CONFIG_MIGRATE:-check}"

# Migrations to check/run, in order. Add new migrations to this array.
MIGRATIONS=(
  "migrations/2025-07-27/reorganize_config_structure.rb"
)

# Check if config directory is writable (for migrations that modify config)
config_is_writable() {
  local config_dir="${APP_ROOT:-$(pwd)}/etc"
  local test_file="$config_dir/.write-test-$$"

  # Try to create a test file
  if touch "$test_file" 2>/dev/null; then
    rm -f "$test_file"
    return 0
  fi
  return 1
}

# Check if a specific migration is needed
# Returns 0 (true) if migration is needed, 1 (false) if not
needs_migration() {
  local migration="$1"

  # Guard for Ruby/Bundler prerequisites
  if ! command -v bundle >/dev/null 2>&1 || ! command -v ruby >/dev/null 2>&1; then
    >&2 echo "SKIP: Requires Ruby and Bundler to check migrations"
    return 1
  fi

  # Fast-fail for yq-required migrations
  if grep -q "which yq" "$migration" && ! command -v yq >/dev/null 2>&1; then
    >&2 echo "SKIP: Migration requires yq - install with: brew install yq"
    return 1
  fi

  bundle exec ruby "$migration" --check >/dev/null 2>&1
  [ $? -eq 1 ]
}

# Check if any migration is needed
any_migration_needed() {
  for migration in "${MIGRATIONS[@]}"; do
    if needs_migration "$migration"; then
      return 0
    fi
  done
  return 1
}

# Run all needed migrations in order
run_migrations() {
  >&2 echo "Running migrations..."

  for migration in "${MIGRATIONS[@]}"; do
    if needs_migration "$migration"; then
      >&2 echo "  Running: $migration"
      bundle exec ruby "$migration" --run
    fi
  done

  >&2 echo "Migrations complete"
}

# Show help with list of pending migrations
show_migration_help() {
  local readonly_note=""
  if ! config_is_writable; then
    readonly_note=" (config mounted read-only)"
  fi

  >&2 echo ""
  >&2 echo "ERROR: Migrations needed before startup${readonly_note}"
  >&2 echo ""
  >&2 echo "Pending migrations:"
  for migration in "${MIGRATIONS[@]}"; do
    if needs_migration "$migration"; then
      >&2 echo "  bundle exec ruby $migration --dry-run"
    fi
  done
  >&2 echo ""
  >&2 echo "Options:"
  >&2 echo "  1. Auto-migrate: Restart with CONFIG_MIGRATE=auto"
  >&2 echo "  2. Manual: Run each migration with --run flag"
  >&2 echo "  3. Skip: Set CONFIG_MIGRATE=skip (not recommended)"
  if ! config_is_writable; then
    >&2 echo ""
    >&2 echo "NOTE: Config directory is read-only. To run migrations:"
    >&2 echo "  - Remove :ro from volume mount, or"
    >&2 echo "  - Run migration on host before starting container"
  fi
  >&2 echo ""
}

# Main logic
case "$CONFIG_MIGRATE" in
  skip)
    >&2 echo "Skipping migration check (CONFIG_MIGRATE=skip)"
    ;;

  auto)
    if any_migration_needed; then
      if ! config_is_writable; then
        >&2 echo ""
        >&2 echo "ERROR: Cannot auto-migrate - config directory is read-only"
        >&2 echo ""
        >&2 echo "To fix: Remove :ro from volume mount, or run migration on host first"
        >&2 echo ""
        exit 1
      fi
      run_migrations
    else
      >&2 echo "All migrations applied"
    fi
    ;;

  *)  # check (default)
    if any_migration_needed; then
      show_migration_help
      exit 1
    else
      >&2 echo "All migrations applied"
    fi
    ;;
esac
