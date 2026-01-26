# Secret Model Migration Spec (V1 → V2)

## Key Pattern

| Aspect | V1 | V2 |
|--------|----|----|
| Prefix | `secret` | `secret` |
| Key Pattern | `secret:{objid}` | `secret:{objid}` |
| Identifier | `objid` (VerifiableIdentifier) | `objid` (VerifiableIdentifier) |
| External ID | N/A | N/A (uses objid directly) |

**No key structure change.** Secret uses VerifiableIdentifier as the public-facing ID.

---

## Field Mapping

### Direct Copy - PRESERVE EXACTLY

**CRITICAL: Never re-encrypt these fields:**

```
ciphertext, value, value_encryption,
passphrase, passphrase_encryption
```

### Direct Copy (No Transform)

```
objid, lifespan, receipt_identifier, receipt_shortid,
created, updated,
share_domain, verification, truncated, secret_key, metadata_key
```

### State Value Transform

| V1 State | V2 State |
|----------|----------|
| `new` | `new` |
| `viewed` | `previewed` |
| `received` | `revealed` |
| `burned` | `burned` |
| `expired` | `expired` |

### Critical Transform

| V1 Field | V2 Field | Transform |
|----------|----------|-----------|
| `custid` (email/`anon`) | `owner_id` (objid/`anon`) | Lookup email → Customer.objid |

**Migration Rule:** If `custid='anon'`, set `owner_id='anon'`. Otherwise lookup Customer by email.

### New V2 Fields (Migration-Only)

| Field | Type | Purpose |
|-------|------|---------|
| `v1_identifier` | String | Original V1 key reference |
| `migration_status` | String | pending/completed/failed/skipped |
| `migrated_at` | Float | Migration timestamp |
| `_original_record` | JsonKey | Complete V1 snapshot |
| `v1_custid` | String | Original email-based custid |
| `v1_original_size` | String | Dropped field preservation |

### Removed Fields

| V1 Field | Action |
|----------|--------|
| `original_size` | Store in `v1_original_size`, remove from main hash |

---

## Redis Data Types

| Type | Key Pattern | Notes |
|------|-------------|-------|
| Hash (main) | `secret:{objid}` | Primary object data |

**Note:** Secret has no subsidiary data types. It's accessed through Receipt.

---

## Indexes to Create

### Instance Index

**No V1 key exists.** Familia v2 automatically maintains `secret:instances` - no manual migration needed.

```redis
# Auto-populated by Familia v2 on save
secret:instances
```

### Lookup Index

| Index | Key | Type | Content |
|-------|-----|------|---------|
| ObjID | `secret:objid_lookup` | Hash | `objid` → `"objid"` (JSON quoted) |

**Note:** No `extid_lookup` - Secret uses VerifiableIdentifier as public ID.

---

## Migration Transform Steps

```ruby
def transform_secret(v1_data, customer_email_to_objid_map)
  v2_data = v1_data.dup
  objid = v1_data[:objid]

  # 1. Store original (CRITICAL for rollback)
  v2_data[:_original_record] = v1_data.to_json
  v2_data[:v1_identifier] = "secret:#{objid}"
  v2_data[:v1_custid] = v1_data[:custid]

  # 2. Transform state values
  v2_data[:state] = case v1_data[:state]
    when 'viewed' then 'previewed'
    when 'received' then 'revealed'
    else v1_data[:state]
  end

  # 3. Transform custid → owner_id
  custid = v1_data[:custid]
  v2_data[:owner_id] = if custid == 'anon'
    'anon'
  else
    customer_email_to_objid_map[custid]
  end

  # 4. Handle removed field
  if v1_data[:original_size]
    v2_data[:v1_original_size] = v1_data[:original_size]
    v2_data.delete(:original_size)
  end

  # 5. Migration status
  v2_data[:migration_status] = 'completed'
  v2_data[:migrated_at] = Time.now.to_f

  # CRITICAL: Preserve encryption fields EXACTLY
  # Do NOT touch: ciphertext, value, value_encryption,
  #               passphrase, passphrase_encryption

  v2_data
end
```

### Index Rebuild

```ruby
def rebuild_secret_indexes(secret)
  objid = secret.objid
  created = secret.created.to_f

  # Instance tracking
  redis.zadd('secret:instances', created, objid)

  # Objid lookup (JSON-quoted)
  redis.hset('secret:objid_lookup', objid, objid.to_json)
end
```

---

## Validation Checklist

### Critical - Encryption Integrity

- [ ] `ciphertext` preserved exactly (binary comparison)
- [ ] `value` preserved exactly
- [ ] `value_encryption` unchanged
- [ ] `passphrase` preserved exactly (hash comparison)
- [ ] `passphrase_encryption` unchanged

### Field Migration

- [ ] `state` values transformed: `viewed`→`previewed`, `received`→`revealed`
- [ ] `owner_id` populated from custid lookup (or 'anon')
- [ ] `v1_custid` stores original custid
- [ ] `v1_original_size` stores dropped field value
- [ ] `_original_record` contains complete V1 data

### Index Population

- [ ] Added to `secret:instances` sorted set
- [ ] Added to `secret:objid_lookup` hash
- [ ] Migration status = 'completed'

### Relationship Integrity

- [ ] `receipt_identifier` still points to valid Receipt
- [ ] `receipt_shortid` matches first 8 chars of receipt objid
