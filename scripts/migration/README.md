# Interaction Modes Migration Script

Atomic migration from `src/views/` + `src/components/` to `src/apps/` structure.

## Prerequisites

```bash
# Install dependencies
pnpm add -D ts-morph fs-extra @types/fs-extra tsx
```

## Usage

```bash
# Dry run - see what would happen without making changes
npx tsx scripts/migration/migrate.ts --dry-run

# Run specific phase only (for debugging)
npx tsx scripts/migration/migrate.ts --dry-run --phase 3

# Execute migration
npx tsx scripts/migration/migrate.ts

# If something goes wrong, rollback
npx tsx scripts/migration/migrate.ts --rollback
```

## Phases

1. **Backup** - Copy `src/` to `src.backup/`
2. **Create Directories** - Build new `apps/` and `shared/` structure
3. **Move Files** - Execute file moves from manifest
4. **Rewrite Imports** - AST-based import path updates
5. **Create New Files** - Generate composables and routers
6. **Validate** - Run type-check and build

## Files

- `migrate.ts` - Main orchestrator script
- `moves.ts` - File move definitions (from manifest)
- `imports.ts` - AST-based import rewriting with ts-morph

## Rollback

If migration fails or produces unexpected results:

```bash
# Automatic rollback from backup
npx tsx scripts/migration/migrate.ts --rollback

# Or manual rollback
rm -rf src
mv src.backup src
```

## After Migration

1. Delete `src.backup/` when confident
2. Delete empty old directories (`src/views/`, `src/components/`, `src/layouts/`)
3. Update any hardcoded paths in config files
4. Run full test suite
