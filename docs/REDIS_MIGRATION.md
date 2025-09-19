# Redis Data Migration Guide

## Overview

Starting with v0.23 and in preparation for v1.0, OneTime Secret defaults to Redis database 0 for all models in new installations. This change improves compatibility with Redis-as-a-Service providers and simplifies connection management.

**For existing installations**: No immediate action required - your current setup will continue working
**For new installations**: All models automatically use database 0

## What Changed

### Legacy Distribution (v0.22.6 and earlier)
Models were distributed across multiple Redis logical databases:
- Database 1: session
- Database 6: customer, custom_domain
- Database 7: metadata
- Database 8: secret, email_receipt
- Database 11: feedback

### New Default (v0.23+)
All models use database 0 by default.

## Automatic Detection and Warnings

When upgrading existing installations, v0.23+ will:

1. Scan Redis databases 0-15 during startup
2. Detect legacy data distribution
3. Display informational warnings (not errors)
4. **Continue normal operation** with your existing data

### Example Startup Message
```
ℹ️  LEGACY DATA DETECTED - No action required

📊 Found existing data in legacy databases:
  • 25 session records in database 1
  • 50 customer records in database 6
  • 75 secret records in database 8

✅ Continuing with existing configuration
💡 Consider migrating to database 0 before v1.0 (see migration guide)
```

## Migration Paths

### Path 1: No Action (Recommended for Most Users)

**Best for**: Existing installations that work fine as-is

- Continue using your current database distribution
- No configuration changes needed
- No downtime required
- Migrate at your convenience before v1.0

### Path 2: Migrate Now (Recommended for New Setups)

**Best for**: Users wanting Redis provider compatibility or simplified setup

Use the built-in migration tool:

```bash
# Preview what will be migrated
bin/ots migrate-redis-data

# Execute the migration
bin/ots migrate-redis-data --run
```

### Path 3: Fresh Start (Data Loss)

**Best for**: Test installations or when starting fresh

> [!WARNING]
> This will make existing secrets and accounts inaccessible.

```bash
export SKIP_LEGACY_DATA_CHECK=true
export ACKNOWLEDGE_DATA_LOSS=true
```

## Migration Tool

### Preview Mode (Safe)
```bash
bin/ots migrate-redis-data
```

Shows migration plan without making changes:
```
📋 Migration Preview:
  • 25 session keys: DB 1 → DB 0
  • 50 customer keys: DB 6 → DB 0
  • 75 secret keys: DB 8 → DB 0

🔍 DRY RUN - No changes made
Add --run flag to execute
```

### Execute Migration
```bash
bin/ots migrate-redis-data --run
```

Performs actual data migration with progress updates.

## Implementation Guide

### For Existing Installations (No Rush)

**Option A: Keep Current Setup**
- No changes needed
- Application continues working normally
- Plan migration before v1.0 release

**Option B: Migrate to Database 0**
1. Stop application
2. Optional: Create backup with ```redis-cli --rdb backup-$(date +%Y%m%d).rdb```
3. Run ```bin/ots migrate-redis-data --run```
4. Start application

### For New Installations

New installations automatically use database 0 - no configuration needed.

### For Docker Users

**Existing containers**: No changes required

**New containers**: Default configuration works out of the box

```bash
# Fresh start example (ignores any existing data in legacy databases)
docker run -p 3000:3000 -d \
  -e SKIP_LEGACY_DATA_CHECK=true \
  -e ACKNOWLEDGE_DATA_LOSS=true \
  onetimesecret/onetimesecret:latest
```

## Advanced Configuration

### Override Database Assignments

To maintain legacy database distribution permanently:

**Environment variables**:
```bash
export REDIS_DBS_SESSION=1
export REDIS_DBS_CUSTOMER=6
export REDIS_DBS_CUSTOM_DOMAIN=6
export REDIS_DBS_METADATA=7
export REDIS_DBS_SECRET=8
export REDIS_DBS_FEEDBACK=11
```

**Configuration file** (```etc/config.yaml```):
```yaml
dbs:
  session: 1
  customer: 6
  custom_domain: 6
  metadata: 7
  secret: 8
  feedback: 11
```

## Reference

### Key Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| ```SKIP_LEGACY_DATA_CHECK``` | Skip startup detection | ```false``` |
| ```ACKNOWLEDGE_DATA_LOSS``` | Proceed despite data loss risk | ```false``` |
| ```REDIS_DBS_*``` | Override specific model database | ```0``` |

### Useful Commands

```bash
# Check Redis connectivity
redis-cli ping

# View data distribution
redis-cli info keyspace

# Safe migration preview
bin/ots migrate-redis-data

# Execute migration
bin/ots migrate-redis-data --run
```

## Timeline

- **v0.23**: New installations default to database 0, existing installations continue unchanged.
- **v0.24+**: Behaviour of v0.23 is maintained, no further changes until major release.
- **v1.0**: All installations use database 0 (migration will be required for legacy setups).
