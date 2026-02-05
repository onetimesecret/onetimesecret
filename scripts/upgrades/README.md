# Upgrade Scripts

Data transformation scripts for major version upgrades. Each version directory
contains scripts to migrate data from the previous version.

## Available Upgrades

| Directory | From | To | Description |
|-----------|------|-----|-------------|
| `v0.24.0/` | 0.23.x | 0.24.0 | Familia v1 to v2 data transforms |

## Structure

Each upgrade directory contains:
- `manifest.yaml` - Transform definitions and execution order
- `run_all.sh` - Execute all transforms in dependency order
- `README.md` - Version-specific documentation
- Numbered subdirectories for each entity type

## Usage

```bash
# Run all transforms for an upgrade
./scripts/upgrades/v0.24.0/run_all.sh

# Run individual transforms
ruby scripts/upgrades/v0.24.0/01-customer/transform.rb --help
```

## Distinction from Migrations

- **Migrations** (`bin/ots migrate`): Schema changes via Familia::Migration
- **Upgrades** (this directory): Bulk data transforms between major versions
