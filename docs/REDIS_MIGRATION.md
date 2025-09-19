# Redis Data Migration Guide

## Overview

Starting with v0.23 and in preparation for v1.0, OneTime Secret now defaults all Redis models to database 0 for new installations. This change improves compatibility with Redis-as-a-Service providers and simplifies connection pooling.

**Previous behavior**: Models were distributed across multiple Redis logical databases (1, 6, 7, 8, 11, 12)
**New behavior**: All models use database 0

## Migration Background

### Legacy Database Distribution (pre-v0.23)

The previous hardcoded database assignments were:

- **Database 1**: session
- **Database 6**: customer, custom_domain
- **Database 7**: metadata
- **Database 8**: secret, email_receipt
- **Database 11**: feedback

To view the number of keys in each database:

```bash
redis-cli info keyspace
```

### Detection and Warning System

When upgrading to v0.23+ with existing data across multiple databases, the application will:

1. Scan databases 0-15 for model data during startup
2. Compare found data against current configuration
3. Display detailed warnings if mismatched data is detected
4. Halt startup to prevent silent data loss

#### Example Warning Output

```
⚠️  WARNING: Legacy data detected in unexpected Redis databases!

📊 LEGACY DATA FOUND:

  Session model (configured for DB 0):
    🔍 Found 25 records in database 1 [was legacy default]
       Sample keys: session:abc123, session:def456, session:ghi789

🔧 RESOLUTION OPTIONS:

  1. UPDATE CONFIGURATION to preserve current data distribution
  2. MIGRATE DATA to database 0 (recommended)
  3. BYPASS CHECK and acknowledge potential data loss
```

## Resolution Options

### Option 1: Update Configuration (Preserve Existing Setup)

Keep your existing database layout by setting environment variables:

```bash
export REDIS_DBS_SESSION=1
export REDIS_DBS_CUSTOMER=6
export REDIS_DBS_CUSTOM_DOMAIN=6
export REDIS_DBS_METADATA=7
export REDIS_DBS_SECRET=8
export REDIS_DBS_FEEDBACK=11
```

**Pros**: No data migration needed, preserves existing setup
**Cons**: Delays migration until v1.0 when it will be required

### Option 2: Migrate to Database 0 (Recommended)

Use the built-in migration tool to consolidate all data to database 0:

```bash
# Preview changes without executing
bin/ots migrate-redis-data

# Perform the actual migration
bin/ots migrate-redis-data --run
```

**Pros**: Modern single-database setup, Redis provider compatibility, future-proof
**Cons**: Requires migration step, brief downtime

### Option 3: Bypass and Acknowledge Data Loss (Fresh Start)

> [!CAUTION]
> **DANGER**: Only use if you understand the implications. Existing accounts and secrets will no longer be accessible.

```bash
export SKIP_LEGACY_DATA_CHECK=true
export ACKNOWLEDGE_DATA_LOSS=true
```

**Consequences**: Data in non-zero databases becomes permanently inaccessible

## Migration Tool Usage

### Preview Mode (Default)

```bash
bin/ots migrate-redis-data
```

Shows what would be migrated without making changes:

```
📋 Migration Plan:
  Total keys to migrate: 150
  • Move 25 session keys: DB 1 → DB 0
  • Move 50 customer keys: DB 6 → DB 0
  • Move 75 secret keys: DB 8 → DB 0

🔍 DRY RUN MODE - No changes will be made
To execute the migration, run with --run flag
```

### Execution Mode

```bash
bin/ots migrate-redis-data --run
```

Performs the actual migration with confirmation prompts:

```
⚠️  WARNING: This will move data between Redis databases.
Make sure you have a backup before proceeding.

Continue with migration? (yes/no): yes

🚀 Starting migration...

📦 Migrating session data (25 keys)...
   From: DB 1 → To: DB 0
   ✅ Successfully migrated 25 session keys

🎉 Migration completed!
```

## Implementation Checklists

> [!NOTE]
> **About Backups**: Consider this an optional step depending on your safety vs security preferences. Weigh the risk of losing unused secrets against dealing with backup files containing sensitive information.

### Pre-Migration Steps

- [ ] **Stop application**: Prevent new data creation during migration
- [ ] **Create Redis backup** (optional): `redis-cli --rdb ./data/backup-$(date +%Y%m%d-%H%M%S).rdb`

### Option 1: Continue with Existing Database Layout

- [ ] **Update configuration** to continue using existing model databases

**Using `etc/config.yaml`**: Replace the `dbs` section with:

```yaml
dbs:
  session: 1
  customer: 6
  custom_domain: 6
  metadata: 7
  secret: 8
  feedback: 11
```

**Using environment variables**: Add to your docker run command:

```bash
-e REDIS_DBS_SESSION=1 \
-e REDIS_DBS_CUSTOM_DOMAIN=6 \
-e REDIS_DBS_CUSTOMER=6 \
-e REDIS_DBS_METADATA=7 \
-e REDIS_DBS_SECRET=8 \
-e REDIS_DBS_FEEDBACK=11
```

### Option 2: Migrate to Database 0

- [ ] **Update configuration**: If using `etc/config.yaml`, set database 0 for all models. Environment variables require no changes.
- [ ] **Run dry run**: Execute migration in preview mode to understand changes
- [ ] **Execute migration**: Add `--run` flag to perform actual migration

### Option 3: Fresh Start (Data Loss)

- [ ] **Add environment variables** to your deployment:

```bash
export SKIP_LEGACY_DATA_CHECK=true
export ACKNOWLEDGE_DATA_LOSS=true
```

**Docker example**:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
    -e SECRET=CHANGEME \
    -e REDIS_URL=redis://host.docker.internal:6379/0 \
    -e SKIP_LEGACY_DATA_CHECK=true \
    -e ACKNOWLEDGE_DATA_LOSS=true \
    onetimesecret/onetimesecret:latest
```

## Reference

### Environment Variables

| Variable | Purpose | Default Value |
|----------|---------|---------------|
| `SKIP_LEGACY_DATA_CHECK` | Bypass startup detection | `false` |
| `ACKNOWLEDGE_DATA_LOSS` | Proceed despite legacy data | `false` |
| `REDIS_DBS_SESSION` | Override session database | `0` |
| `REDIS_DBS_CUSTOMER` | Override customer database | `0` |
| `REDIS_DBS_CUSTOM_DOMAIN` | Override custom domain database | `0` |
| `REDIS_DBS_METADATA` | Override metadata database | `0` |
| `REDIS_DBS_SECRET` | Override secret database | `0` |
| `REDIS_DBS_FEEDBACK` | Override feedback database | `0` |

### Useful Commands

```bash
# Test Redis connectivity
redis-cli ping

# View database key distribution
redis-cli info keyspace

# Run migration (safe to run multiple times)
bin/ots migrate-redis-data --run
```
