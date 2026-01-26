# Receipt Model Migration Spec (V1 → V2)

## Key Pattern

| Aspect | V1 | V2 |
|--------|----|----|
| Model Name | `Onetime::Metadata` | `Onetime::Receipt` |
| Prefix | `metadata` | `receipt` |
| Key Pattern | `metadata:{objid}:object` | `receipt:{objid}:object` |
| Identifier | `objid` (VerifiableIdentifier) | `objid` (VerifiableIdentifier) |
| External ID | N/A | N/A (uses objid directly) |

**Key prefix change:** `metadata` → `receipt`

---

## Field Mapping

### Direct Copy (No Transform)

```
objid, secret_identifier, secret_shortid, secret_ttl,
lifespan, share_domain, passphrase, recipients, memo,
created, updated, burned, shared, truncate, secret_key, key
```

### Field Renames

| V1 Field | V2 Field | Notes |
|----------|----------|-------|
| `viewed` | `previewed` | Copy to both for compat |
| `received` | `revealed` | Copy to both for compat |

### State Value Transform

| V1 State | V2 State |
|----------|----------|
| `new` | `new` |
| `viewed` | `previewed` |
| `received` | `revealed` |
| `burned` | `burned` |
| `expired` | `expired` |
| `orphaned` | `orphaned` |

### Critical Transform

| V1 Field | V2 Field | Transform |
|----------|----------|-----------|
| `custid` (email/`anon`) | `owner_id` (objid/`anon`) | Lookup email → Customer.objid |

**Migration Rule:** If `custid='anon'`, set `owner_id='anon'`. Otherwise lookup Customer by email.

### New V2 Fields

| Field | Type | Purpose |
|-------|------|---------|
| `owner_id` | String | Customer objid (replaces custid) |
| `org_id` | String | Organization objid (optional, from owner) |
| `domain_id` | String | CustomDomain objid (optional, from share_domain) |
| `previewed` | String | Renamed from `viewed` |
| `revealed` | String | Renamed from `received` |
| `v1_key` | String | Original `metadata:{id}:object` key |
| `v1_custid` | String | Original email-based custid |
| `v1_identifier` | String | Base migration tracking |
| `migration_status` | String | pending/completed/failed/skipped |
| `migrated_at` | String | Migration timestamp |
| `_original_record` | JsonKey | Complete V1 snapshot |

### Removed Fields

| V1 Field | V2 Status | Notes |
|----------|-----------|-------|
| `custid` | Replaced | Use `owner_id` |
| `viewed` | Deprecated | Keep for compat, use `previewed` |
| `received` | Deprecated | Keep for compat, use `revealed` |

---

## Redis Data Types

| Type | Key Pattern | Notes |
|------|-------------|-------|
| Hash (main) | `receipt:{objid}:object` | Primary object data |

---

## Indexes to Create

### Instance Index

**No V1 key exists.** Not required for migration.

### Expiration Timeline

```redis
ZADD receipt:expiration_timeline <expires_at> <objid>
```

### Warnings Sent Tracking

```redis
SADD receipt:warnings_sent <objid>  # If warning already sent
```

### Lookup Index

| Index | Key | Type | Content |
|-------|-----|------|---------|
| ObjID | `receipt:objid_lookup` | Hash | `objid` → `"objid"` (JSON quoted) |

### Relationship Participation

```redis
# Organization participation
ZADD organization:{org_id}:receipts <created_timestamp> <objid>

# CustomDomain participation (if domain_id set)
ZADD customdomain:{domain_id}:receipts <created_timestamp> <objid>
```

---

## Migration Transform Steps

```ruby
def transform_receipt(v1_data, customer_email_to_objid_map, domain_fqdn_to_id_map)
  v2_data = {}
  objid = v1_data[:objid]

  # 1. Store original
  v2_data[:_original_record] = v1_data.to_json
  v2_data[:v1_identifier] = "metadata:#{objid}:object"
  v2_data[:v1_key] = "metadata:#{objid}:object"
  v2_data[:v1_custid] = v1_data[:custid]

  # 2. Copy direct fields
  %i[objid secret_identifier secret_shortid secret_ttl
     lifespan share_domain passphrase recipients memo
     created updated burned shared truncate secret_key key].each do |field|
    v2_data[field] = v1_data[field] if v1_data[field]
  end

  # 3. Rename fields (keep both for compat)
  v2_data[:previewed] = v1_data[:viewed]
  v2_data[:viewed] = v1_data[:viewed]  # Keep deprecated
  v2_data[:revealed] = v1_data[:received]
  v2_data[:received] = v1_data[:received]  # Keep deprecated

  # 4. Transform state
  v2_data[:state] = case v1_data[:state]
    when 'viewed' then 'previewed'
    when 'received' then 'revealed'
    else v1_data[:state]
  end

  # 5. Transform custid → owner_id
  custid = v1_data[:custid]
  v2_data[:owner_id] = if custid == 'anon'
    'anon'
  else
    customer_email_to_objid_map[custid]
  end

  # 6. Set org_id from owner's organization (optional)
  if v2_data[:owner_id] && v2_data[:owner_id] != 'anon'
    customer = Customer.load(v2_data[:owner_id])
    v2_data[:org_id] = customer&.organization&.objid
  end

  # 7. Set domain_id from share_domain (optional)
  if v1_data[:share_domain]
    v2_data[:domain_id] = domain_fqdn_to_id_map[v1_data[:share_domain]]
  end

  # 8. Migration status
  v2_data[:migration_status] = 'completed'
  v2_data[:migrated_at] = Time.now.to_f.to_s

  v2_data
end
```

### Index Rebuild

```ruby
def rebuild_receipt_indexes(receipt)
  objid = receipt.objid
  created = receipt.created.to_f

  # Instance tracking
  redis.zadd('receipt:instances', created, objid)

  # Expiration timeline (if secret has expiration)
  if receipt.secret_ttl && receipt.created
    expires_at = receipt.created.to_f + receipt.secret_ttl.to_i
    redis.zadd('receipt:expiration_timeline', expires_at, objid)
  end

  # Objid lookup (JSON-quoted)
  redis.hset('receipt:objid_lookup', objid, objid.to_json)

  # Organization participation
  if receipt.org_id
    redis.zadd("organization:#{receipt.org_id}:receipts", created, objid)
  end

  # Domain participation
  if receipt.domain_id
    redis.zadd("customdomain:#{receipt.domain_id}:receipts", created, objid)
  end

  # Customer receipts (for backwards compat)
  if receipt.owner_id && receipt.owner_id != 'anon'
    redis.zadd("customer:#{receipt.owner_id}:receipts", created, objid)
  end
end
```

---

## Validation Checklist

### Key Migration

- [ ] Source key `metadata:{objid}:object` read correctly
- [ ] Target key `receipt:{objid}:object` written correctly
- [ ] `v1_key` stores original key path

### Field Migration

- [ ] `state` values transformed: `viewed`→`previewed`, `received`→`revealed`
- [ ] `owner_id` populated from custid lookup (or 'anon')
- [ ] `previewed` populated from `viewed` value
- [ ] `revealed` populated from `received` value
- [ ] `v1_custid` stores original custid
- [ ] `org_id` set from owner's organization (if applicable)
- [ ] `domain_id` set from share_domain lookup (if applicable)
- [ ] `_original_record` contains complete V1 data

### Index Population

- [ ] Added to `receipt:instances` sorted set
- [ ] Added to `receipt:expiration_timeline` (if has expiration)
- [ ] Added to `receipt:objid_lookup` hash
- [ ] Added to `organization:{org_id}:receipts` (if org_id set)
- [ ] Added to `customdomain:{domain_id}:receipts` (if domain_id set)
- [ ] Added to `customer:{owner_id}:receipts` (if owner_id not anon)
- [ ] Migration status = 'completed'

### Relationship Integrity

- [ ] `secret_identifier` still points to valid Secret
- [ ] `secret_shortid` matches first 8 chars of secret objid
