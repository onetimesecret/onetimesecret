MODEL MIGRATION SPEC: Secret
Version: 1.0
Phase: 5 of 5 (based on directory prefix)

DEPENDENCIES

Requires
  - Phase 1 Customer migration (provides email_to_objid mapping)

Provides
  - None

KEY PATTERN

V1: secret:{objid}
V2: secret:{objid}

Change: None

FIELD TRANSFORMS

Direct Copy (no transform)
  objid, lifespan, receipt_identifier, receipt_shortid, created, updated,
  share_domain, verification, truncated, secret_key, metadata_key

Transforms
  custid (email) -> owner_id (objid)     Lookup: email_to_objid[custid]
  custid (email) -> v1_custid            Preserve original
  state: 'viewed' -> state: 'previewed'  Value transform
  state: 'received' -> state: 'revealed' Value transform
  original_size -> v1_original_size      Move and delete original

New Fields (migration-only)
  v1_identifier       String    Original V1 key for rollback
  migration_status    String    pending/migrating/completed/failed/skipped
  migrated_at         Float     Unix timestamp of completion
  _original_record    JSON      Complete V1 snapshot

Removed Fields
  original_size       Moved to v1_original_size

RELATED DATA TYPES

Type        Key Pattern        Action
(none)

INDEXES

Instance Index
  V2 key: secret:instances (sorted set, score=created timestamp)

Lookup Indexes
  secret:objid_lookup       Hash    objid -> "objid" (JSON quoted)

Participation Indexes
  (none)

TRANSFORM PSEUDOCODE

transform(v1_record, mappings):
  v2 = copy(v1_record)

  # CRITICAL: Do not re-encrypt these fields.
  # ciphertext, value, value_encryption, passphrase, passphrase_encryption
  # These are carried over by the initial `copy`.

  # Store original for rollback
  v2._original_record = json(v1_record)
  v2.v1_identifier = v1_record.key  # Full V1 key path for rollback
  v2.v1_custid = v1.custid

  # Field transforms
  if v1.custid == 'anon':
    v2.owner_id = 'anon'
  else:
    v2.owner_id = mappings.email_to_objid[v1.custid]

  v2.state = transform_state(v1_record.state) # 'viewed'->'previewed', etc.

  # Handle removed field
  if v1_record.original_size:
    v2.v1_original_size = v1_record.original_size
    v2.delete(original_size)

  # Status
  v2.migration_status = 'completed'
  v2.migrated_at = now()

  return v2

INDEX REBUILD PSEUDOCODE

rebuild_indexes(v2_record):
  objid = v2_record.objid
  created = v2_record.created

  # Instance tracking
  ZADD secret:instances created objid

  # Lookup index
  HSET secret:objid_lookup objid json(objid)

VALIDATION CHECKLIST

[ ] `ciphertext` preserved exactly (binary comparison)
[ ] `passphrase` preserved exactly (hash comparison)
[ ] `state` values transformed correctly
[ ] `owner_id` populated from `custid` (or 'anon')
[ ] `v1_original_size` stores dropped field value
[ ] `_original_record` contains complete V1 data
[ ] Added to `secret:instances`
[ ] Added to `secret:objid_lookup`
[ ] Migration status = 'completed'

WARNINGS

CRITICAL: Do not re-encrypt `ciphertext`, `value`, or `passphrase` fields. They must be preserved exactly as they are in the V1 record.

NOTE: Anonymous records use custid='anon', set owner_id='anon' (no lookup).
