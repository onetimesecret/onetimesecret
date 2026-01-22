#!/bin/bash
# Export metadata tables to SQL files for version control
#
# Usage: bash locales/scripts/export-metadata.sh
#
# Exports session_log, glossary, and schema_migrations tables
# from the ephemeral tasks.db to tracked .sql files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_FILE="$SCRIPT_DIR/../db/tasks.db"
DB_DIR="$SCRIPT_DIR/../db"

# Metadata tables to export (single source of truth for shell script)
# Note: Also defined in store.py:286 - keep in sync
METADATA_TABLES="session_log glossary schema_migrations"

if [ ! -f "$DB_FILE" ]; then
  echo "Error: Database not found at $DB_FILE"
  echo "Run: python locales/scripts/store.py hydrate --from-json"
  exit 1
fi

if [ ! -w "$DB_DIR" ]; then
  echo "Error: Cannot write to $DB_DIR"
  exit 1
fi

echo "Exporting metadata tables..."

for table in $METADATA_TABLES; do
  # Validate table name
  case "$table" in
    session_log|glossary|schema_migrations) ;;
    *) echo "Error: Invalid table name $table"; exit 1 ;;
  esac

  sqlite3 "$DB_FILE" <<EOF > "$DB_DIR/${table}.sql"
.mode insert $table
SELECT * FROM $table;
EOF
  echo "  ✓ ${table}.sql"
done

echo ""
echo "Metadata exported to locales/db/*.sql"
echo "Remember to stage these files:"
echo "  git add locales/db/*.sql"
