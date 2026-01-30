# Migration Fields Cheatsheet

Quick reference for v1→v2 data migration using Familia migration features.

## Base Feature: `with_migration_fields`

All models include this via `feature :with_migration_fields`.

### Fields Added to All Models

| Field | Type | Purpose |
|-------|------|---------|
| `v1_identifier` | String | Original v1 key for rollback reference |
| `migration_status` | String | pending/migrating/completed/failed/skipped |
| `migrated_at` | Float | Timestamp of migration completion |
| `_original_record` | jsonkey | Complete v1 data snapshot |

### Status Constants

```ruby
MIGRATION_STATUS = {
  pending: 'pending',
  in_progress: 'migrating',
  completed: 'completed',
  failed: 'failed',
  skipped: 'skipped'
}
```

### Key Methods

```ruby
# Mark record as migrated
record.mark_migrated!(v1_id)

# Mark migration failed (stores error in caboose)
record.mark_migration_failed!(error)

# Status checks
record.migrated?           # => true if completed
record.migration_pending?  # => true if nil or pending

# Store/retrieve metadata in caboose
record.store_migration_metadata('key', value)
record.migration_metadata('key')

# Store complete v1 record for rollback/audit
record.store_original_record(
  object_data,                    # Hash of original fields
  data_types_data: {},            # Related data_types (hashkeys, lists, etc)
  key: 'original:redis:key',
  db: 6,
  exported_at: Time.now
)

# Access stored original data
record.original_record      # => full stored hash
record.original_object      # => just the object fields
record.original_data_type('brand')  # => specific data_type value
record.original_record?     # => true if stored

# Capture current data_types before transformation
record.snapshot_data_types  # => { 'brand' => {...}, 'sessions' => [...] }
```

### Class Methods

```ruby
# Find records by status
Model.pending_migration(:pending)  # default
Model.pending_migration(:failed)

# Get migration stats
Model.migration_stats  # => { 'pending' => 100, 'completed' => 50 }
```

---

## Model-Specific Features

### Customer (`customer_migration_fields`)

**Extra field:** `v1_custid` (original email-based custid)

```ruby
# Build email→objid mapping for lookups
Customer.build_email_mapping  # => { 'user@example.com' => 'objid123' }

# Find by v1 email
Customer.find_by_v1_custid('user@example.com')

# Migrate billing to organization
customer.migrate_billing_to_organization!  # copies stripe_* to default org
customer.needs_billing_migration?
```

### Organization (`organization_migration_fields`)

**Extra field:** `v1_source_custid` (email of source customer)
**Extra jsonkey:** `caboose` (migration metadata + payment link info)

```ruby
# Create org from v1 customer
Organization.create_from_v1_customer!(customer, v1_data)

# Find by source customer email
Organization.find_by_v1_source('user@example.com')

# Store payment link info in caboose
org.store_payment_link_info(v1_data)
org.payment_link_info  # => { 'plan' => 'identity', 'interval' => 'monthly' }

# Check if from v1 migration
org.from_v1_migration?

# Store v1 source info
org.store_v1_source('user@example.com', 'cus_stripe_id')
```

### CustomDomain (`custom_domain_migration_fields`)

**Extra field:** `v1_custid` (original email-based owner)

```ruby
# Find domains needing org migration
CustomDomain.pending_org_migration

# Build v1 owner mapping
CustomDomain.build_v1_owner_mapping  # => { 'email' => ['domainid1', 'domainid2'] }

# Migrate to organization
domain.migrate_to_org!(email_to_org_mapping)
domain.needs_org_migration?
domain.organization  # => Organization instance
```

### Receipt (`receipt_migration_fields`)

**Extra fields:** `v1_key`, `v1_custid`

```ruby
# Find receipts needing migration
Receipt.pending_owner_migration
Receipt.ownership_stats  # => { anonymous: 100, authenticated: 50 }

# Migrate owner
receipt.migrate_owner!(email_to_objid_mapping, email_to_org_mapping)
receipt.needs_owner_migration?
receipt.anonymous_receipt?

# Migrate field names (viewed→previewed, received→revealed)
receipt.migrate_field_names!
```

### Secret (`secret_migration_fields`)

**Extra fields:** `v1_custid`, `v1_original_size`

```ruby
# Find secrets needing migration
Secret.pending_owner_migration
Secret.encryption_stats   # => { '1' => 100, '2' => 50 }
Secret.ownership_stats    # => { anonymous: 100, authenticated: 50 }

# Migrate owner (does NOT re-encrypt)
secret.migrate_owner!(email_to_objid_mapping)
secret.needs_owner_migration?
secret.anonymous_secret?

# Preserve dropped field
secret.preserve_original_size(size)

# Check encryption version
secret.encryption_version  # => :empty, :none, :v1, :v2, :unknown
```

---

## Typical Migration Flow

```ruby
# 1. Load v1 data from dump
v1_data = JSON.parse(File.read('customer_dump.json'))

# 2. Create/load v2 record
customer = Customer.new(objid: generate_uuid_v7)

# 3. Store original for rollback
customer.store_original_record(
  v1_data['object'],
  data_types_data: v1_data['data_types'],
  key: v1_data['key'],
  db: v1_data['db'],
  exported_at: v1_data['exported_at']
)

# 4. Transform fields
customer.custid = customer.objid  # v2 uses objid as custid
customer.v1_custid = v1_data['object']['custid']  # preserve email
customer.email = v1_data['object']['custid']
# ... other field mappings

# 5. Save and mark migrated
customer.save
customer.mark_migrated!(v1_data['key'])

# On failure:
# customer.mark_migration_failed!(error)
```

---

## Removal Checklist (Post-Migration)

1. Remove `feature :with_migration_fields` from all model files
2. Remove model-specific migration features from model files
3. Delete feature files:
   - `lib/onetime/models/features/with_migration_fields.rb`
   - `lib/onetime/models/*/features/migration_fields.rb`
4. Remove `require_relative 'features/migration_fields'` from customer/features.rb
5. Remove `jsonkey :caboose` from Organization (or repurpose)
6. Run validation to ensure all records are migrated
7. Optionally clean up `_original_record` data from Redis
