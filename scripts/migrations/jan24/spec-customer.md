# Customer Model Migration Spec (V1 → V2)

## Key Pattern

| Aspect | V1 | V2 |
|--------|----|----|
| Prefix | `customer` | `customer` |
| Key Pattern | `customer:{objid}` | `customer:{objid}` |
| Identifier | `objid` (UUID v7) | `objid` (UUID v7) |
| External ID | `ur%<id>s` (e.g., `ur0abc123`) | `ur%<id>s` |

**No key structure change** - same prefix and pattern.

---

## Field Mapping

### Direct Copy (No Transform)

All existing V1 fields map directly:

```
objid, extid, custid, email, locale, planid,
last_password_update, last_login, notify_on_reveal,
role, joined, verified, verified_by,
secrets_created, secrets_burned, secrets_shared, emails_sent,
sessid, apitoken, contributor,
stripe_customer_id, stripe_subscription_id,
passphrase, passphrase_encryption, value, value_encryption
```

### Critical Transform

| V1 Field | V2 Field | Transform |
|----------|----------|-----------|
| `custid` | `custid` | For legacy records where `custid=email`, it should equal `objid` in V2 |

**Migration Rule:** If V1 `custid` equals email address, store original in `v1_custid` and set `custid = objid`.

### New V2 Fields (Migration-Only)

| Field | Type | Purpose |
|-------|------|---------|
| `v1_identifier` | String | Original V1 key for rollback |
| `migration_status` | String | `pending`/`migrating`/`completed`/`failed`/`skipped` |
| `migrated_at` | String | Migration completion timestamp |
| `_original_record` | JsonKey | Complete V1 record for rollback/audit |
| `v1_custid` | String | Original email-based custid (if different from objid) |

### Removed Fields

None. All V1 fields preserved (deprecated fields kept for backward compat).

---

## Redis Data Types

| Type | Key Pattern | Notes |
|------|-------------|-------|
| Hash (main) | `customer:{objid}` | Primary object data |
| Sorted Set | `customer:{objid}:receipts` | Customer's receipts |
| Hash | `customer:{objid}:feature_flags` | Feature toggles |
| String | `customer:{objid}:reset_secret` | Password reset token (24h TTL) |
| Sorted Set | `customer:{objid}:custom_domain` | Deprecated - domains now on Organization |
| JsonKey | `customer:{objid}:_original_record` | **V2 only** - V1 backup |

---

## Indexes to Create

### Instance Index

**V1 key exists:** `onetime:customer` (sorted set, 368 entries) - legacy naming convention.

```redis
# Rename the existing key
RENAME onetime:customer customer:instances
```

### Lookup Indexes

| Index | Key | Type | Content |
|-------|-----|------|---------|
| Email → objid | `customer:email_index` | Hash | `email` → `"objid"` (JSON quoted) |
| ExtID → objid | `customer:extid_lookup` | Hash | `extid` → `"objid"` (JSON quoted) |
| ObjID → objid | `customer:objid_lookup` | Hash | `objid` → `"objid"` (JSON quoted) |

### Role Index

```redis
SADD customer:role_index:colonel <objid>
SADD customer:role_index:customer <objid>
SADD customer:role_index:anonymous <objid>
```

### Class Counters (Global)

| Counter | Key |
|---------|-----|
| secrets_created | `customer:secrets_created` |
| secrets_shared | `customer:secrets_shared` |
| secrets_burned | `customer:secrets_burned` |
| emails_sent | `customer:emails_sent` |

---

## Migration Transform Steps

```ruby
def transform_customer(v1_data)
  v2_data = v1_data.dup

  # 1. Store original record
  v2_data[:_original_record] = v1_data.to_json
  v2_data[:v1_identifier] = "customer:#{v1_data[:objid]}"

  # 2. Handle custid migration (email → objid)
  if v1_data[:custid] != v1_data[:objid]
    v2_data[:v1_custid] = v1_data[:custid]
    v2_data[:custid] = v1_data[:objid]
  end

  # 3. Set migration status
  v2_data[:migration_status] = 'completed'
  v2_data[:migrated_at] = Time.now.to_f.to_s

  v2_data
end
```

### Index Rebuild

```ruby
def rebuild_customer_indexes(customer)
  objid = customer.objid
  created = customer.created.to_f

  # Instance tracking
  redis.zadd('customer:instances', created, objid)

  # Lookup indexes (JSON-quoted values)
  redis.hset('customer:email_index', customer.email, objid.to_json)
  redis.hset('customer:extid_lookup', customer.extid, objid.to_json)
  redis.hset('customer:objid_lookup', objid, objid.to_json)

  # Role index
  redis.sadd("customer:role_index:#{customer.role}", objid) if customer.role
end
```

---

## Validation Checklist

- [ ] All hash fields copied
- [ ] `v1_custid` populated if custid was email
- [ ] `custid` equals `objid`
- [ ] `_original_record` contains complete V1 data
- [ ] Added to `customer:instances` sorted set
- [ ] Added to `customer:email_index`
- [ ] Added to `customer:extid_lookup`
- [ ] Added to `customer:objid_lookup`
- [ ] Added to appropriate `customer:role_index:{role}`
- [ ] Migration status = 'completed'
