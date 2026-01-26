MODEL MIGRATION SPEC: Customer
Version: 1.0
Phase: 1 of 5 (based on directory prefix)

DEPENDENCIES

Requires
  - None

Provides
  - email_to_objid mapping (for subsequent phases)
  - extid_to_objid mapping (for subsequent phases)

KEY PATTERN

V1: customer:{custid}
V2: customer:{objid}

Change: Identifier change (custid (email) -> objid (UUID v7))

FIELD TRANSFORMS

Direct Copy (no transform)
  objid, extid, email, locale, planid, last_password_update, last_login,
  notify_on_reveal, role, joined, verified, verified_by, secrets_created,
  secrets_burned, secrets_shared, emails_sent, sessid, apitoken,
  contributor, stripe_customer_id, stripe_subscription_id, passphrase,
  passphrase_encryption, value, value_encryption

Transforms
  custid (email) -> custid (objid)     Lookup: sets custid = objid
  custid (email) -> v1_custid            Preserve original if custid != objid

New Fields (migration-only)
  v1_identifier       String    Original V1 key for rollback
  migration_status    String    pending/migrating/completed/failed/skipped
  migrated_at         Float     Unix timestamp of completion
  _original_record    JSON      Complete V1 snapshot

Removed Fields
  None

RELATED DATA TYPES

Type        Key Pattern                      Action
Sorted Set  customer:{objid}:receipts        Rename from :metadata
Hash        customer:{objid}:feature_flags   Copy as-is
String      customer:{objid}:reset_secret    Copy as-is (with TTL)
Sorted Set  customer:{objid}:custom_domain   Copy as-is (deprecated)

INDEXES

Instance Index
  V1 key: onetime:customer (rename to customer:instances)

Lookup Indexes
  customer:email_index        Hash    email -> "objid" (JSON quoted)
  customer:extid_lookup       Hash    extid -> "objid"
  customer:objid_lookup       Hash    objid -> "objid"

Participation Indexes
  customer:role_index:{role}    Set    Add objid to set based on role

TRANSFORM PSEUDOCODE

transform(v1_record, mappings):
  v2 = copy(v1_record)

  # Store original for rollback
  v2._original_record = json(v1_record)
  v2.v1_identifier = "customer:{v1.objid}"

  # Field transforms: Handle custid migration (email → objid)
  if v1.custid != v1.objid:
    v2.v1_custid = v1.custid
    v2.custid = v1.objid

  # Status
  v2.migration_status = 'completed'
  v2.migrated_at = Familia.now()

  return v2

INDEX REBUILD PSEUDOCODE

rebuild_indexes(v2_record):
  objid = v2_record.objid
  created = v2_record.created

  # Instance tracking
  ZADD customer:instances created objid

  # Lookup indexes (JSON-quoted values)
  HSET customer:email_index v2_record.email json(objid)
  HSET customer:extid_lookup v2_record.extid json(objid)
  HSET customer:objid_lookup objid json(objid)

  # Participation (Role index)
  if v2_record.role:
    SADD customer:role_index:{v2_record.role} objid

VALIDATION CHECKLIST

[ ] All hash fields copied
[ ] v1_custid populated if custid was email
[ ] custid equals objid
[ ] _original_record contains complete V1 data
[ ] Added to customer:instances
[ ] Added to customer:email_index
[ ] Added to customer:extid_lookup
[ ] Added to customer:objid_lookup
[ ] Added to appropriate customer:role_index:{role}
[ ] Migration status = 'completed'
[ ] Record count matches: V1 count == V2 count

WARNINGS

CRITICAL: Do not re-encrypt ciphertext or passphrase fields. Preserve exactly.

NOTE: The V1 instance index uses the prefix `onetime:` not `customer:` (`onetime:customer`). This key must be added to the `dump_keys.rb` MODEL_MAPPING to be included in the data dump.
