MODEL MIGRATION SPEC: CustomDomain
Version: 1.0
Phase: 3 of 5 (based on directory prefix)

DEPENDENCIES

Requires
  - Phase 1 Customer migration (provides email_to_objid mapping)
  - Phase 2 Organization migration (provides email_to_org_objid mapping)

Provides
  - fqdn_to_domain_objid mapping (for Receipt phase)

KEY PATTERN

V1: customdomain:{domainid}
V2: customdomain:{domainid}

Change: None. V2 adds an external ID (`extid`).

FIELD TRANSFORMS

Direct Copy (no transform)
  domainid, display_domain, base_domain, subdomain, trd, tld, sld,
  txt_validation_host, txt_validation_value, status, vhost, verified,
  resolving, created, updated, _original_value

Transforms
  custid (email) -> org_id (objid)     Lookup: email_to_org_objid[custid]
  custid (email) -> v1_custid            Preserve original

New Fields (migration-only)
  objid               String    Primary identifier (alias for domainid)
  extid               String    External ID for public-facing URLs
  v1_identifier       String    Original V1 key for rollback
  migration_status    String    pending/migrating/completed/failed/skipped
  migrated_at         Float     Unix timestamp of completion
  _original_record    JSON      Complete V1 snapshot

Removed Fields
  custid      Replaced by org_id
  values      (class set) Replaced by `instances` sorted set index

RELATED DATA TYPES

Type        Key Pattern                      Action
Hash        customdomain:{id}:brand          Copy as-is
Hash        customdomain:{id}:logo           Copy as-is
Hash        customdomain:{id}:icon           Copy as-is

INDEXES

Instance Index
  V1 key: customdomain:values (rename to customdomain:instances)

Lookup Indexes
  customdomain:display_domain_index  Hash    fqdn -> "domainid" (JSON quoted)
  customdomain:display_domains       Hash    fqdn -> "domainid" (legacy compat)
  customdomain:extid_lookup          Hash    extid -> "domainid"
  customdomain:objid_lookup          Hash    domainid -> "domainid"
  customdomain:owners                Hash    domainid -> "org_id"

Participation Indexes
  organization:{org_id}:domains    Sorted Set    Add domainid with score=created

TRANSFORM PSEUDOCODE

transform(v1_record, mappings):
  v2 = copy(v1_record)
  domainid = v1_record.domainid

  # Store original for rollback
  v2._original_record = json(v1_record)
  v2.v1_identifier = "customdomain:{domainid}"
  v2.v1_custid = v1_record.custid

  # Field transforms
  v2.org_id = mappings.email_to_org_objid[v1_record.custid]
  v2.delete(custid)

  # New Fields
  v2.objid = domainid
  v2.extid = "cd" + domainid[0..7]

  # Status
  v2.migration_status = 'completed'
  v2.migrated_at = now()

  return v2

INDEX REBUILD PSEUDOCODE

rebuild_indexes(v2_record):
  domainid = v2_record.domainid
  created = v2_record.created

  # Instance tracking
  ZADD customdomain:instances created domainid

  # Lookup indexes (JSON-quoted values)
  HSET customdomain:display_domain_index v2_record.display_domain json(domainid)
  HSET customdomain:display_domains v2_record.display_domain json(domainid)
  HSET customdomain:extid_lookup v2_record.extid json(domainid)
  HSET customdomain:objid_lookup domainid json(domainid)
  HSET customdomain:owners domainid json(v2_record.org_id)

  # Participation (if applicable)
  ZADD organization:{v2_record.org_id}:domains created domainid

VALIDATION CHECKLIST

[ ] All hash fields copied
[ ] v1_custid stores original email-based custid
[ ] org_id points to a valid Organization objid
[ ] extid generated in `cd{id}` format
[ ] objid equals domainid
[ ] Brand/logo/icon hashes migrated correctly
[ ] Added to customdomain:instances
[ ] Added to lookup indexes (display_domain, extid, objid, owners)
[ ] Added to organization:{org_id}:domains
[ ] Migration status = 'completed'
[ ] Record count matches: V1 count == V2 count
