MODEL MIGRATION SPEC: Receipt
Version: 1.0
Phase: 4 of 5 (based on directory prefix)

DEPENDENCIES

Requires
  - Phase 1 Customer migration (provides email_to_objid mapping)
  - Phase 2 Organization migration (provides org_objid for linking)
  - Phase 3 CustomDomain migration (provides fqdn_to_domain_objid mapping)

Provides
  - None

KEY PATTERN

V1: metadata:{objid}:object
V2: receipt:{objid}:object

Change: Prefix change (metadata -> receipt)

FIELD TRANSFORMS

Direct Copy (no transform)
  objid, secret_identifier, secret_shortid, secret_ttl, lifespan,
  share_domain, passphrase, recipients, memo, created, updated, burned,
  shared, truncate, secret_key, key

Transforms
  custid (email) -> owner_id (customer objid)     Lookup: email_to_objid[custid]
  custid (email) -> org_id (customer->organization.objid)
  custid (email) -> v1_custid            Preserve original
  state: 'viewed' -> state: 'previewed'  Value transform
  state: 'received' -> state: 'revealed' Value transform
  viewed -> previewed                    Rename (keep original for compat)
  received -> revealed                 Rename (keep original for compat)

New Fields (migration-only)
  org_id              String    Inferred Organization objid
  domain_id           String    Inferred CustomDomain objid
  v1_key              String    Original V1 key for rollback
  v1_identifier       String    Base migration tracking
  migration_status    String    pending/migrating/completed/failed/skipped
  migrated_at         Float     Unix timestamp of completion
  _original_record    JSON      Complete V1 snapshot

Removed Fields
  custid      Replaced by owner_id

RELATED DATA TYPES

Type        Key Pattern        Action
(none)

INDEXES

Instance Index
  V2 key: receipt:instances (sorted set, score=created timestamp)

Lookup Indexes
  receipt:objid_lookup       Hash    objid -> "objid" (JSON quoted)

Participation Indexes
  organization:{org_id}:receipts    Sorted Set    Add objid with score=created
  customdomain:{domain_id}:receipts Sorted Set    Add objid with score=created
  customer:{owner_id}:receipts      Sorted Set    Add objid (for V1 compat)

Other Indexes
  receipt:expiration_timeline   Sorted Set    score=expires_at, value=objid
  receipt:warnings_sent         Set           objid

TRANSFORM PSEUDOCODE

transform(v1_record, mappings):
  v2 = copy_direct_fields(v1_record)

  # Store original for rollback
  v2._original_record = json(v1_record)
  v2.v1_identifier = v1_record.key  # Full V1 key path for rollback
  v2.v1_key = v2.v1_identifier
  v2.v1_custid = v1.custid

  # Field renames (keeping original for backward compatibility)
  v2.previewed = v1_record.viewed
  v2.revealed = v1_record.received

  # State transform
  v2.state = transform_state(v1_record.state) # 'viewed'->'previewed', etc.

  # Link owner
  if v1.custid == 'anon':
    v2.owner_id = 'anon'
  else:
    v2.owner_id = mappings.email_to_objid[v1.custid]

  # Link organization and domain
  if v2.owner_id != 'anon':
    v2.org_id = get_org_from_owner(v2.owner_id)
  if v1.share_domain:
    v2.domain_id = mappings.fqdn_to_domain_objid[v1.share_domain]

  # Status
  v2.migration_status = 'completed'
  v2.migrated_at = now()

  return v2

INDEX REBUILD PSEUDOCODE

rebuild_indexes(v2_record):
  objid = v2_record.objid
  created = v2_record.created

  # Instance tracking
  ZADD receipt:instances created objid

  # Expiration timeline
  if v2_record.secret_ttl:
    expires_at = created + v2_record.secret_ttl
    ZADD receipt:expiration_timeline expires_at objid

  # Lookup index
  HSET receipt:objid_lookup objid json(objid)

  # Participation
  if v2_record.org_id:
    ZADD organization:{v2_record.org_id}:receipts created objid
  if v2_record.domain_id:
    ZADD customdomain:{v2_record.domain_id}:receipts created objid
  if v2_record.owner_id and v2_record.owner_id != 'anon':
    ZADD customer:{v2_record.owner_id}:receipts created objid


VALIDATION CHECKLIST

[ ] `receipt:{objid}:object` written correctly
[ ] `v1_key` stores original `metadata:...` key path
[ ] `state` values transformed ('viewed' -> 'previewed')
[ ] `owner_id` populated from `custid` (or 'anon')
[ ] `org_id` and `domain_id` linked correctly
[ ] Added to `receipt:instances`
[ ] Added to `receipt:expiration_timeline` if applicable
[ ] Added to `receipt:objid_lookup`
[ ] Added to participation indexes (organization, customdomain, customer)
[ ] Migration status = 'completed'

WARNINGS

CRITICAL: Do not re-encrypt ciphertext or passphrase fields. Preserve exactly.

NOTE: Anonymous records use custid='anon', set owner_id='anon' (no lookup).
NOTE: Field `viewed` is renamed to `previewed`, and `received` to `revealed`. The original fields are kept for backward compatibility during the transition.
