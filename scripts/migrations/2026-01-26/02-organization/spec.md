MODEL MIGRATION SPEC: Organization
Version: 1.0
Phase: 2 of 5 (based on directory prefix)

DEPENDENCIES

Requires
  - Phase 1 Customer migration (reads Customer records to create Organizations)

Provides
  - org_objid for subsequent phases (CustomDomain, Receipt)
  - organization:contact_email_index mapping
  - organization:stripe_customer_id_index mapping

KEY PATTERN

V1: N/A (New model)
V2: organization:{objid}:object

Change: New model in V2. Organizations are created 1-for-1 from V1 Customer records.

FIELD TRANSFORMS

Source Fields (from Customer)
  Customer.objid             -> owner_id
  Customer.email             -> contact_email, billing_email
  Customer.stripe_customer_id  -> stripe_customer_id
  Customer.stripe_subscription_id -> stripe_subscription_id
  Customer.planid            -> planid

New Fields (generated during migration)
  objid, extid, display_name, description, is_default, subscription_status, ...

New Fields (migration-only)
  caboose             JsonKey   Migration metadata + payment link info
  v1_identifier       String    Original key reference (from Customer)
  migration_status    String    pending/completed/failed
  migrated_at         Float     Unix timestamp of completion
  _original_record    JSON      Snapshot of the source Customer record
  v1_source_custid    String    Source customer email

Removed Fields
  None

RELATED DATA TYPES

Type        Key Pattern                                Action
Hash        organization:{objid}:urls                  New in V2
Sorted Set  organization:{objid}:pending_invitations   New in V2
JsonKey     organization:{objid}:caboose               New in V2
JsonKey     organization:{objid}:_original_record    New in V2 (migration snapshot)

INDEXES

Instance Index
  V2 key: organization:instances (sorted set, score=created timestamp)

Lookup Indexes
  organization:contact_email_index          Hash    email -> "objid"
  organization:stripe_customer_id_index     Hash    cus_xxx -> "objid"
  organization:stripe_subscription_id_index Hash    sub_xxx -> "objid"
  organization:stripe_checkout_email_index  Hash    email -> "objid"
  organization:extid_lookup                 Hash    extid -> "objid"
  organization:objid_lookup                 Hash    objid -> "objid"

Participation Indexes
  organization:{objid}:members    Sorted Set    Add customer objids with score=joined
  organization:{objid}:domains    Sorted Set    Add CustomDomain objids with score=created
  organization:{objid}:receipts   Sorted Set    Add Receipt objids with score=created

TRANSFORM PSEUDOCODE

transform(v1_customer_record, mappings):
  v2_org = {}

  # Create new identifiers
  v2_org.objid = generate_id()
  v2_org.extid = "on" + v2_org.objid[0..7]

  # Set fields from source customer
  v2_org.owner_id = v1_customer_record.objid
  v2_org.contact_email = v1_customer_record.email
  v2_org.billing_email = v1_customer_record.email
  v2_org.stripe_customer_id = v1_customer_record.stripe_customer_id
  v2_org.stripe_subscription_id = v1_customer_record.stripe_subscription_id
  v2_org.planid = v1_customer_record.planid

  # Set default and generated fields
  v2_org.display_name = derive_display_name(v1_customer_record.email)
  v2_org.is_default = true

  # Store original for rollback
  v2_org._original_record = json(v1_customer_record)
  v2_org.v1_identifier = "customer:{v1_customer_record.objid}"
  v2_org.v1_source_custid = v1_customer_record.email

  # Status
  v2_org.migration_status = 'completed'
  v2_org.migrated_at = now()

  return v2_org

INDEX REBUILD PSEUDOCODE

rebuild_indexes(v2_record):
  objid = v2_record.objid
  created = v2_record.created

  # Instance tracking
  ZADD organization:instances created objid

  # Lookup indexes
  HSET organization:contact_email_index v2_record.contact_email json(objid)
  HSET organization:extid_lookup v2_record.extid json(objid)
  HSET organization:objid_lookup objid json(objid)
  if v2_record.stripe_customer_id:
    HSET organization:stripe_customer_id_index v2_record.stripe_customer_id json(objid)
  if v2_record.stripe_subscription_id:
    HSET organization:stripe_subscription_id_index v2_record.stripe_subscription_id json(objid)

  # Participation (add owner as first member)
  ZADD organization:{objid}:members created v2_record.owner_id

VALIDATION CHECKLIST

[ ] Organization created with valid objid
[ ] extid generated in on{id} format
[ ] owner_id references valid Customer
[ ] contact_email set from customer email
[ ] Stripe billing fields transferred from customer
[ ] is_default = true for migrated orgs
[ ] Added to organization:instances
[ ] Added to organization:contact_email_index
[ ] Added to organization:extid_lookup
[ ] Added to organization:objid_lookup
[ ] Stripe indexes populated if applicable
[ ] Owner added to organization:{objid}:members
[ ] Migration status = 'completed'

WARNINGS

CRITICAL: Do not re-encrypt ciphertext or passphrase fields. Preserve exactly.

NOTE: Organization is a new model in V2. Records are created from V1 Customer data, not transformed from V1 Organization data.
