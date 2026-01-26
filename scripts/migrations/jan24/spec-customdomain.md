# CustomDomain Model Migration Spec (V1 → V2)

## Key Pattern

| Aspect | V1 | V2 |
|--------|----|----|
| Prefix | `customdomain` | `customdomain` |
| Key Pattern | `customdomain:{domainid}` | `customdomain:{domainid}` |
| Identifier | `domainid` (random base-36) | `domainid` (alias for `objid`) |
| External ID | N/A | `cd%<id>s` (e.g., `cd1a2b3c4`) |

**Key change:** V2 adds external identifier (`extid`) for public-facing URLs.

---

## Field Mapping

### Direct Copy (No Transform)

```
domainid, display_domain, base_domain, subdomain,
trd, tld, sld,
txt_validation_host, txt_validation_value,
status, vhost, verified, resolving,
created, updated, _original_value
```

### Critical Transform

| V1 Field | V2 Field | Transform |
|----------|----------|-----------|
| `custid` (email) | `org_id` (Organization objid) | Lookup customer → organization |

**Migration Rule:** Lookup Customer by email, then get their default Organization objid.

### New V2 Fields

| Field | Type | Purpose |
|-------|------|---------|
| `objid` | String | Primary identifier (equals domainid) |
| `extid` | String | External ID format: `cd{short_id}` |
| `org_id` | String | Organization foreign key (replaces custid) |
| `v1_identifier` | String | Original V1 key reference |
| `migration_status` | String | pending/completed/failed/skipped |
| `migrated_at` | String | Migration timestamp |
| `v1_custid` | String | Original email-based custid |
| `_original_record` | JsonKey | Complete V1 snapshot |

### Removed/Replaced Fields

| V1 Field | V2 Status | Notes |
|----------|-----------|-------|
| `custid` | Replaced | Use `org_id` (Organization objid) |
| `values` (class set) | Removed | Replaced by `instances` sorted set |

---

## Redis Data Types

| Type | Key Pattern | Notes |
|------|-------------|-------|
| Hash (main) | `customdomain:{domainid}` | Primary object data |
| Hash | `customdomain:{domainid}:brand` | Branding config |
| Hash | `customdomain:{domainid}:logo` | Logo config |
| Hash | `customdomain:{domainid}:icon` | Icon config |
| JsonKey | `customdomain:{domainid}:_original_record` | V2 only |

---

## Indexes to Create

### Instance Index

**V1 key exists:** `customdomain:values` (sorted set)

```redis
# Rename the existing key
RENAME customdomain:values customdomain:instances
```

### Lookup Indexes

| Index | Key | Type | Content |
|-------|-----|------|---------|
| Display Domain (unique) | `customdomain:display_domain_index` | Hash | `fqdn` → `"domainid"` |
| Display Domain (compat) | `customdomain:display_domains` | Hash | `fqdn` → `"domainid"` |
| ExtID | `customdomain:extid_lookup` | Hash | `extid` → `"domainid"` |
| ObjID | `customdomain:objid_lookup` | Hash | `domainid` → `"domainid"` |
| Owners | `customdomain:owners` | Hash | `domainid` → `"org_id"` |

### Organization Participation

```redis
ZADD organization:{org_id}:domains <created_timestamp> <domainid>
```

---

## Migration Transform Steps

```ruby
def transform_customdomain(v1_data, customer_email_to_org_map)
  v2_data = v1_data.dup
  domainid = v1_data[:domainid]

  # 1. Store original
  v2_data[:_original_record] = v1_data.to_json
  v2_data[:v1_identifier] = "customdomain:#{domainid}"
  v2_data[:v1_custid] = v1_data[:custid]

  # 2. Transform custid → org_id
  org_id = customer_email_to_org_map[v1_data[:custid]]
  v2_data[:org_id] = org_id
  v2_data.delete(:custid)  # Remove deprecated field

  # 3. Generate external ID
  v2_data[:extid] = "cd#{domainid[0..7]}"

  # 4. Ensure objid equals domainid
  v2_data[:objid] = domainid

  # 5. Migration status
  v2_data[:migration_status] = 'completed'
  v2_data[:migrated_at] = Time.now.to_f.to_s

  v2_data
end
```

### Index Rebuild

```ruby
def rebuild_customdomain_indexes(domain)
  domainid = domain.domainid
  created = domain.created.to_f

  # Instance tracking
  redis.zadd('customdomain:instances', created, domainid)

  # Display domain indexes (JSON-quoted)
  redis.hset('customdomain:display_domain_index', domain.display_domain, domainid.to_json)
  redis.hset('customdomain:display_domains', domain.display_domain, domainid.to_json)

  # Identifier lookups
  redis.hset('customdomain:extid_lookup', domain.extid, domainid.to_json)
  redis.hset('customdomain:objid_lookup', domainid, domainid.to_json)

  # Owner mapping
  redis.hset('customdomain:owners', domainid, domain.org_id.to_json)

  # Organization participation
  redis.zadd("organization:#{domain.org_id}:domains", created, domainid)
end
```

---

## Validation Checklist

- [ ] All hash fields copied
- [ ] `v1_custid` stores original email-based custid
- [ ] `org_id` points to valid Organization objid
- [ ] `extid` generated in `cd{id}` format
- [ ] `objid` equals `domainid`
- [ ] Brand/logo/icon hashes migrated
- [ ] Added to `customdomain:instances`
- [ ] Added to `customdomain:display_domain_index`
- [ ] Added to `customdomain:display_domains`
- [ ] Added to `customdomain:extid_lookup`
- [ ] Added to `customdomain:objid_lookup`
- [ ] Added to `customdomain:owners`
- [ ] Added to `organization:{org_id}:domains`
- [ ] Migration status = 'completed'
