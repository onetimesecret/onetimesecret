# Upgrade Scripts

Data transformation scripts for major version upgrades. Each version directory
contains scripts to migrate data from the previous version.

## Available Upgrades

None currently. Historical upgrade pipelines are preserved at their release
tags rather than carried forward on main:

| Pipeline   | From   | To     | Where to find it                            |
| ---------- | ------ | ------ | ------------------------------------------- |
| `v0.24.5/` | 0.23.x | 0.24.5 | `git checkout v0.24.5 -- scripts/upgrades/` |

If you are upgrading from 0.23.x, run the pipeline from the v0.24.5 release
checkout, then upgrade normally from there.

## Structure

Each upgrade directory contains:

- `manifest.yaml` - Transform definitions and execution order
- `run_pipeline.sh` - Execute all transforms in dependency order
- `README.md` - Version-specific documentation
- Numbered subdirectories for each entity type

## Distinction from Migrations

- **Migrations** (`bin/ots migrate`): Schema changes via Familia::Migration
- **Upgrades** (this directory): Bulk data transforms between major versions
