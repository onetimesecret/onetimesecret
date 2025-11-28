#!/bin/bash

##
# CONFIG MIGRATION CHECK SCRIPT (2025-11-27)
#
# Checks if config migrations are needed by delegating to the
# migration scripts themselves (single source of truth).
#
# Usage:
#   ./check-config-migration.sh
#
# Environment:
#   CONFIG_MIGRATE=check (default) - Check and halt if migration needed
#   CONFIG_MIGRATE=auto            - Automatically run migrations
#   CONFIG_MIGRATE=skip            - Skip migration check entirely
#
# Exit codes:
#   0 - Config is up to date or migrations completed
#   1 - Migration needed (check mode) or migration failed
#

set -e

CONFIG_MIGRATE="${CONFIG_MIGRATE:-check}"

MIGRATION_01="migrations/20250727-1523_01_convert_symbol_keys.rb"
MIGRATION_02="migrations/20250727-1523_02_reorganize_config_structure.rb"

# Check if migration 01 is needed (symbol keys)
# Uses the migration's own logic via --check flag
needs_migration_01() {
  bundle exec ruby "$MIGRATION_01" --check >/dev/null 2>&1
  [ $? -eq 1 ]
}

# Check if migration 02 is needed (config structure)
# Uses the migration's own logic via --check flag
needs_migration_02() {
  bundle exec ruby "$MIGRATION_02" --check >/dev/null 2>&1
  [ $? -eq 1 ]
}

run_migrations() {
  >&2 echo "Running config migrations..."

  if needs_migration_01; then
    >&2 echo "  Migration 01: Converting symbol keys..."
    bundle exec ruby "$MIGRATION_01" --run
  fi

  if needs_migration_02; then
    >&2 echo "  Migration 02: Reorganizing config structure..."
    bundle exec ruby "$MIGRATION_02" --run
  fi

  >&2 echo "Config migrations complete"
}

show_migration_help() {
  local issue="$1"

  >&2 echo ""
  >&2 echo "ERROR: Config file needs migration ($issue)"
  >&2 echo ""
  >&2 echo "Options:"
  >&2 echo "  1. Auto-migrate: Restart with CONFIG_MIGRATE=auto"
  >&2 echo "  2. Manual: Run in container:"
  >&2 echo "       bundle exec ruby $MIGRATION_01 --run"
  >&2 echo "       bundle exec ruby $MIGRATION_02 --run"
  >&2 echo "  3. Skip: Set CONFIG_MIGRATE=skip (not recommended)"
  >&2 echo ""
}

# Main logic
case "$CONFIG_MIGRATE" in
  skip)
    >&2 echo "Skipping config migration check (CONFIG_MIGRATE=skip)"
    ;;

  auto)
    if needs_migration_01 || needs_migration_02; then
      run_migrations
    else
      >&2 echo "Config is up to date"
    fi
    ;;

  *)  # check (default)
    if needs_migration_01; then
      show_migration_help "symbol keys detected"
      exit 1
    elif needs_migration_02; then
      show_migration_help "old structure detected"
      exit 1
    else
      >&2 echo "Config is up to date"
    fi
    ;;
esac
