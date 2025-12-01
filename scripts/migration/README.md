# Interaction Modes Migration Script

Atomic migration from `src/views/` + `src/components/` to `src/apps/` structure.

## Prerequisites

```bash
# Install dependencies
pnpm add -D ts-morph fs-extra @types/fs-extra tsx
```

## Quick Start (Recommended)

```bash
# Fully automated - runs until complete or gives up
pnpx tsx scripts/migration/auto-migrate.ts --unattended

# Interactive - prompts on each failure
pnpx tsx scripts/migration/auto-migrate.ts

# Preview first
pnpx tsx scripts/migration/auto-migrate.ts --dry-run
```

## Manual Usage

```bash
# Dry run - see what would happen without making changes
pnpx tsx scripts/migration/migrate.ts --dry-run

# Run specific phase only (for debugging)
pnpx tsx scripts/migration/migrate.ts --dry-run --phase 3

# Execute migration
pnpx tsx scripts/migration/migrate.ts

# If something goes wrong, rollback
pnpx tsx scripts/migration/migrate.ts --rollback
```

## Phases

1. **Backup** - Copy `src/` to `src.backup/`
2. **Create Directories** - Build new `apps/` and `shared/` structure
3. **Move Files** - Execute file moves from manifest
4. **Rewrite Imports** - AST-based import path updates
5. **Create New Files** - Generate composables and routers
6. **Validate** - Run type-check and build

## Files

| File | Purpose |
|------|---------|
| `auto-migrate.ts` | Iterative runner with auto-retry and error recovery |
| `migrate.ts` | Core migration orchestrator (6 phases) |
| `moves.ts` | File move definitions (from manifest) |
| `imports.ts` | AST-based import rewriting with ts-morph |

## Auto-Migration Features

The `auto-migrate.ts` runner provides:

- **Iterative execution** - Runs phases in sequence
- **Auto-retry** - Retries failed phases up to 3 times
- **Error analysis** - Recognizes common error patterns
- **Auto-fix** - Applies fixes for known issues (missing dirs, duplicates)
- **Interactive mode** - Prompts for guidance on failure
- **Unattended mode** - Fully automated with `--unattended`
- **Logging** - Full log written to `migration.log`

### Error Patterns Handled

- Missing directories → Auto-create
- Duplicate destination files → Compare and dedupe
- Unresolved imports → Log for manual review
- Type errors → Log for manual review

## Rollback

If migration fails or produces unexpected results:

```bash
# Automatic rollback from backup
pnpx tsx scripts/migration/auto-migrate.ts --rollback

# Or manual rollback
rm -rf src
mv src.backup src
```

## After Migration

1. Delete `src.backup/` when confident
2. Delete empty old directories (`src/views/`, `src/components/`, `src/layouts/`)
3. Update any hardcoded paths in config files
4. Run full test suite
