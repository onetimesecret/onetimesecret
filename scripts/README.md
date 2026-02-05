# Scripts

Utility and operational scripts for Onetime Secret.

## Directories

- `upgrades/` - Data transformation scripts for major version upgrades
- `s6-rc.d/` - s6 service definitions for container supervision

## Scripts

| Script | Purpose |
|--------|---------|
| `api_validation.rb` | API endpoint validation |
| `check-migration-status.sh` | Check Familia migration status |
| `entrypoint.sh` | Docker container entrypoint |
| `update-file-headers.rb` | Update source file headers |
| `update-version.sh` | Update version numbers across codebase |
