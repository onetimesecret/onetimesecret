#!/bin/bash

# scripts/check-migration-status.sh

##
# MIGRATION STATUS CHECK SCRIPT (2025-11-27)
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
  "migrations/20250727-1523_01_convert_symbol_keys.rb"
)

# Check if a specific migration is needed
# Returns 0 (true) if migration is needed, 1 (false) if not
needs_migration() {
  local migration="$1"
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
  >&2 echo ""
  >&2 echo "ERROR: Migrations needed before startup"
  >&2 echo ""
  >&2 echo "Pending migrations:"
  for migration in "${MIGRATIONS[@]}"; do
    if needs_migration "$migration"; then
      >&2 echo "  - $migration"
    fi
  done
  >&2 echo ""
  >&2 echo "Options:"
  >&2 echo "  1. Auto-migrate: Restart with CONFIG_MIGRATE=auto"
  >&2 echo "  2. Manual: Run each migration with --run flag"
  >&2 echo "  3. Skip: Set CONFIG_MIGRATE=skip (not recommended)"
  >&2 echo ""
}

# Main logic
case "$CONFIG_MIGRATE" in
  skip)
    >&2 echo "Skipping migration check (CONFIG_MIGRATE=skip)"
    ;;

  auto)
    if any_migration_needed; then
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
