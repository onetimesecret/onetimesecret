#!/usr/bin/env bash
#
# Reorganize authentication migrations
#
# This script reorganizes the migration files to:
# 1. Move indexes to 002 (right after table creation)
# 2. Renumber functions to 003
# 3. Renumber triggers to 004
# 4. Split old 004_views_indexes_policies into:
#    - 005_views
#    - 006_policies
#
# Run from the repository root:
#   $ bash apps/web/auth/migrations/reorganize_migrations.sh
#

set -euo pipefail

# Base directory
MIGRATION_DIR="apps/web/auth/migrations"
POSTGRES_DIR="$MIGRATION_DIR/schemas/postgres"
SQLITE_DIR="$MIGRATION_DIR/schemas/sqlite"

echo "==================================================================="
echo "Reorganizing authentication migrations"
echo "==================================================================="
echo ""

# Ensure we're in the repository root
if [ ! -d "$MIGRATION_DIR" ]; then
  echo "Error: Must run from repository root"
  exit 1
fi

# Step 1: Rename Ruby migration files
echo "Step 1: Renaming Ruby migration files..."
echo "  002_functions.rb → 003_functions.rb"
git mv "$MIGRATION_DIR/002_functions.rb" "$MIGRATION_DIR/003_functions.rb"

echo "  003_triggers.rb → 004_triggers.rb"
git mv "$MIGRATION_DIR/003_triggers.rb" "$MIGRATION_DIR/004_triggers.rb"

echo "  Removing old 004_views_indexes_policies.rb (split into 005_views and 006_policies)"
git rm "$MIGRATION_DIR/004_views_indexes_policies.rb"

echo ""

# Step 2: Update migration version comments in Ruby files
echo "Step 2: Updating migration version comments..."
echo "  Updating 003_functions.rb comments..."
sed -i '' 's/-M 2 /-M 3 /g' "$MIGRATION_DIR/003_functions.rb"
sed -i '' 's/-M 1 /-M 2 /g' "$MIGRATION_DIR/003_functions.rb"
sed -i '' 's/002_functions\.rb/003_functions.rb/g' "$MIGRATION_DIR/003_functions.rb"
sed -i '' 's/002_functions_/003_functions_/g' "$MIGRATION_DIR/003_functions.rb"

echo "  Updating 004_triggers.rb comments..."
sed -i '' 's/-M 3 /-M 4 /g' "$MIGRATION_DIR/004_triggers.rb"
sed -i '' 's/-M 2 /-M 3 /g' "$MIGRATION_DIR/004_triggers.rb"
sed -i '' 's/003_triggers\.rb/004_triggers.rb/g' "$MIGRATION_DIR/004_triggers.rb"
sed -i '' 's/003_triggers_/004_triggers_/g' "$MIGRATION_DIR/004_triggers.rb"

echo ""

# Step 3: Rename PostgreSQL SQL files
echo "Step 3: Renaming PostgreSQL SQL files..."
echo "  002_functions_⬆.sql → 003_functions_⬆.sql"
git mv "$POSTGRES_DIR/002_functions_⬆.sql" "$POSTGRES_DIR/003_functions_⬆.sql"

echo "  002_functions_⬇.sql → 003_functions_⬇.sql"
git mv "$POSTGRES_DIR/002_functions_⬇.sql" "$POSTGRES_DIR/003_functions_⬇.sql"

echo "  003_triggers_⬆.sql → 004_triggers_⬆.sql"
git mv "$POSTGRES_DIR/003_triggers_⬆.sql" "$POSTGRES_DIR/004_triggers_⬆.sql"

echo "  003_triggers_⬇.sql → 004_triggers_⬇.sql"
git mv "$POSTGRES_DIR/003_triggers_⬇.sql" "$POSTGRES_DIR/004_triggers_⬇.sql"

echo "  Removing old 004_views_indexes_policies_⬆.sql"
git rm "$POSTGRES_DIR/004_views_indexes_policies_⬆.sql"

echo "  Removing old 004_views_indexes_policies_⬇.sql"
git rm "$POSTGRES_DIR/004_views_indexes_policies_⬇.sql"

echo ""

# Step 4: Rename SQLite SQL files
echo "Step 4: Renaming SQLite SQL files..."
echo "  002_functions_⬆.sql → 003_functions_⬆.sql"
git mv "$SQLITE_DIR/002_functions_⬆.sql" "$SQLITE_DIR/003_functions_⬆.sql"

echo "  002_functions_⬇.sql → 003_functions_⬇.sql"
git mv "$SQLITE_DIR/002_functions_⬇.sql" "$SQLITE_DIR/003_functions_⬇.sql"

echo "  003_triggers_⬆.sql → 004_triggers_⬆.sql"
git mv "$SQLITE_DIR/003_triggers_⬆.sql" "$SQLITE_DIR/004_triggers_⬆.sql"

echo "  003_triggers_⬇.sql → 004_triggers_⬇.sql"
git mv "$SQLITE_DIR/003_triggers_⬇.sql" "$SQLITE_DIR/004_triggers_⬇.sql"

echo "  Removing old 004_views_indexes_policies_⬆.sql"
git rm "$SQLITE_DIR/004_views_indexes_policies_⬆.sql"

echo "  Removing old 004_views_indexes_policies_⬇.sql"
git rm "$SQLITE_DIR/004_views_indexes_policies_⬇.sql"

echo ""

# Step 5: Update header comments in PostgreSQL SQL files
echo "Step 5: Updating header comments in PostgreSQL SQL files..."
echo "  Updating 003_functions_⬆.sql..."
sed -i '' 's/Rodauth PostgreSQL Functions (002)/Rodauth PostgreSQL Functions (003)/g' "$POSTGRES_DIR/003_functions_⬆.sql"
sed -i '' 's/003_functions\.rb/003_functions.rb/g' "$POSTGRES_DIR/003_functions_⬆.sql"

echo "  Updating 003_functions_⬇.sql..."
sed -i '' 's/Rodauth PostgreSQL Functions Rollback (002)/Rodauth PostgreSQL Functions Rollback (003)/g' "$POSTGRES_DIR/003_functions_⬇.sql"

echo "  Updating 004_triggers_⬆.sql..."
sed -i '' 's/Rodauth PostgreSQL Triggers (003)/Rodauth PostgreSQL Triggers (004)/g' "$POSTGRES_DIR/004_triggers_⬆.sql"
sed -i '' 's/004_triggers\.rb/004_triggers.rb/g' "$POSTGRES_DIR/004_triggers_⬆.sql"

echo "  Updating 004_triggers_⬇.sql..."
sed -i '' 's/Rodauth PostgreSQL Triggers Rollback (003)/Rodauth PostgreSQL Triggers Rollback (004)/g' "$POSTGRES_DIR/004_triggers_⬇.sql"

echo ""

# Step 6: Update header comments in SQLite SQL files
echo "Step 6: Updating header comments in SQLite SQL files..."
echo "  Updating 003_functions_⬆.sql..."
sed -i '' 's/Rodauth SQLite Functions (002)/Rodauth SQLite Functions (003)/g' "$SQLITE_DIR/003_functions_⬆.sql"
sed -i '' 's/003_functions\.rb/003_functions.rb/g' "$SQLITE_DIR/003_functions_⬆.sql"

echo "  Updating 003_functions_⬇.sql..."
sed -i '' 's/Rodauth SQLite Functions Rollback (002)/Rodauth SQLite Functions Rollback (003)/g' "$SQLITE_DIR/003_functions_⬇.sql"

echo "  Updating 004_triggers_⬆.sql..."
sed -i '' 's/Rodauth SQLite Triggers (003)/Rodauth SQLite Triggers (004)/g' "$SQLITE_DIR/004_triggers_⬆.sql"
sed -i '' 's/004_triggers\.rb/004_triggers.rb/g' "$SQLITE_DIR/004_triggers_⬆.sql"

echo "  Updating 004_triggers_⬇.sql..."
sed -i '' 's/Rodauth SQLite Triggers Rollback (003)/Rodauth SQLite Triggers Rollback (004)/g' "$SQLITE_DIR/004_triggers_⬇.sql"

echo ""

# Step 7: Git add new files
echo "Step 7: Adding new migration files to git..."
git add "$MIGRATION_DIR/002_indexes.rb"
git add "$MIGRATION_DIR/005_views.rb"
git add "$MIGRATION_DIR/006_policies.rb"
git add "$POSTGRES_DIR/002_indexes_⬆.sql"
git add "$POSTGRES_DIR/002_indexes_⬇.sql"
git add "$POSTGRES_DIR/005_views_⬆.sql"
git add "$POSTGRES_DIR/005_views_⬇.sql"
git add "$POSTGRES_DIR/006_policies_⬆.sql"
git add "$POSTGRES_DIR/006_policies_⬇.sql"
git add "$SQLITE_DIR/002_indexes_⬆.sql"
git add "$SQLITE_DIR/002_indexes_⬇.sql"
git add "$SQLITE_DIR/005_views_⬆.sql"
git add "$SQLITE_DIR/005_views_⬇.sql"
git add "$SQLITE_DIR/006_policies_⬆.sql"
git add "$SQLITE_DIR/006_policies_⬇.sql"

echo ""
echo "==================================================================="
echo "Migration reorganization complete!"
echo "==================================================================="
echo ""
echo "New migration structure:"
echo "  001_initial.rb         - Table definitions"
echo "  002_indexes.rb         - Performance indexes (NEW)"
echo "  003_functions.rb       - Database functions (was 002)"
echo "  004_triggers.rb        - Database triggers (was 003)"
echo "  005_views.rb           - Convenience views (NEW, extracted from 004)"
echo "  006_policies.rb        - RLS policies (NEW, extracted from 004)"
echo ""
echo "Review changes with:"
echo "  git status"
echo "  git diff --staged"
echo ""
echo "Commit when ready:"
echo "  git commit -m '[#2215] Reorganize migrations: move indexes to 002, split views/policies'"
echo ""
