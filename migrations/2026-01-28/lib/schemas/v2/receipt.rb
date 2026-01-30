# migrations/2026-01-28/lib/schemas/v2/receipt.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 receipt data (output after transformation).
      #
      # V2 receipts (formerly "metadata") track secret lifecycle with:
      # - UUIDv7 objid (generated from metadata key for determinism)
      # - extid for URL paths (rc prefix)
      # - owner_id linking to customer objid
      # - org_id linking to organization objid
      # - domain_id linking to custom domain objid (optional)
      #
      RECEIPT = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Receipt V2',
        'description' => 'V2 receipt record after migration transformation',
        'type' => 'object',
        'required' => %w[objid key migration_status migrated_at],
        'properties' => {
          # New primary identifier (UUIDv7)
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URL paths
          'extid' => {
            'type' => 'string',
            'pattern' => '^rc[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Secret key this receipt tracks (preserved from V1)
          'key' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Secret key this receipt tracks',
          },

          # Owner customer objid (resolved from custid)
          'owner_id' => {
            'type' => %w[string null],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid (resolved from customer email)
          'org_id' => {
            'type' => %w[string null],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # Custom domain objid (resolved from share_domain if present)
          'domain_id' => {
            'type' => %w[string null],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Custom domain objid (UUIDv7, optional)',
          },

          # Original V1 custid (email) preserved for audit
          'v1_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer identifier (email)',
          },

          # Original V1 Redis key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^metadata:.+:object$',
            'description' => 'Original V1 Redis key',
          },

          # Migration tracking
          'migration_status' => {
            'type' => 'string',
            'enum' => %w[pending completed failed],
            'description' => 'Migration status',
          },
          'migrated_at' => {
            'type' => 'string',
            'pattern' => '^\\d+(\\.\\d+)?$',
            'description' => 'Migration timestamp (epoch float as string)',
          },

          # Lifecycle state (preserved from V1)
          'state' => {
            'type' => 'string',
            'enum' => %w[new viewed received burned],
            'description' => 'Receipt/secret lifecycle state',
          },

          # Short key for display
          'secret_shortkey' => {
            'type' => 'string',
            'description' => 'Short version of secret key for display',
          },

          # Recipients (preserved from V1)
          'recipients' => {
            'type' => 'string',
            'description' => 'Comma-separated recipient emails',
          },

          # Timestamps (carried forward)
          'created' => {
            'type' => 'string',
            'pattern' => '^\\d+(\\.\\d+)?$',
            'description' => 'Creation timestamp (epoch float as string)',
          },
          'updated' => {
            'type' => 'string',
            'pattern' => '^\\d+(\\.\\d+)?$',
            'description' => 'Last update timestamp (epoch float as string)',
          },

          # Passphrase indicator
          'passphrase_temp' => {
            'type' => 'string',
            'description' => 'Temporary passphrase indicator',
          },

          # Original share domain FQDN (preserved for audit)
          'share_domain' => {
            'type' => 'string',
            'description' => 'Custom domain FQDN used for sharing',
          },

          # TTL in seconds
          'ttl' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Time-to-live in seconds',
          },

          # View count
          'view_count' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Number of times viewed',
          },

          # Received timestamp
          'received' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?)?$',  # Allow empty string
            'description' => 'Timestamp when secret was received',
          },

          # Burned timestamp
          'burned' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?)?$',  # Allow empty string
            'description' => 'Timestamp when secret was burned (destroyed by owner)',
          },

          # TTL duration set when created
          'lifespan' => {
            'type' => 'string',
            'pattern' => '^(\\d+)?$',  # Allow empty string
            'description' => 'TTL duration in seconds (V1 field name)',
          },

          # Optional memo/subject for incoming secrets
          'memo' => {
            'type' => 'string',
            'description' => 'Optional memo or subject for incoming secrets',
          },

          # Passphrase indicator/value
          'passphrase' => {
            'type' => 'string',
            'description' => 'Passphrase indicator or encrypted value',
          },

          # Full secret key reference
          'secret_key' => {
            'type' => 'string',
            'description' => 'Full secret key reference',
          },

          # Time-to-live in seconds for the secret
          'secret_ttl' => {
            'type' => 'string',
            'pattern' => '^(\\d+)?$',  # Allow empty string
            'description' => 'Time-to-live in seconds for the secret',
          },

          # Shared timestamp
          'shared' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?)?$',  # Allow empty string
            'description' => 'Timestamp when secret was shared',
          },

          # Receipt token/identifier
          'token' => {
            'type' => 'string',
            'description' => 'Receipt token/identifier',
          },

          # Truncation indicator
          'truncate' => {
            'type' => 'string',
            'enum' => ['true', 'false', '0', '1', ''],  # Allow empty string
            'description' => 'Whether content was truncated',
          },

          # Viewed timestamp (by owner)
          'viewed' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?)?$',  # Allow empty string
            'description' => 'Timestamp when secret was previewed by owner',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:receipt_v2, RECEIPT)
    end
  end
end


__END__

## Source Files
- Ruby Schema: migrations/2026-01-28/lib/schemas/v2/receipt.rb
- Spec.md: migrations/2026-01-26/04-metadata/spec.md
- Zod Schema: src/schemas/models/receipt.ts

---
Receipt (highest discrepancy count)
┌─────────────────┬──────────────────────────────────────────────────────────┬──────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│    Category     │                       Ruby Schema                        │                   Spec.md                    │                                                Zod (truth)                                                 │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ State enum      │ Missing: shared, revealed, previewed, expired, orphaned  │ Documents transform                          │ Has all values                                                                                             │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Field renames   │ secret_shortkey→secret_shortid                           │ Uses both naming conventions                 │ Uses secret_shortid                                                                                        │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Boolean flags   │ Missing all is_* flags                                   │ Missing all                                  │ Has 8: is_viewed, is_received, is_previewed, is_revealed, is_burned, is_destroyed, is_expired, is_orphaned │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Timestamps      │ Missing: shared, viewed, previewed, revealed, burned     │ Has some                                     │ Has all as nullable dates                                                                                  │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Missing fields  │ shortid, receipt_ttl, has_passphrase, secret_state, memo │ Missing: shortid, receipt_ttl, boolean flags │ Has all                                                                                                    │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Computed fields │ Missing all                                              │ Missing all                                  │ natural_expiration, expiration, expiration_in_seconds, paths, URLs                                         │
├─────────────────┼──────────────────────────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Security        │ Has passphrase, secret_key                               │ Same                                         │ Has has_passphrase (boolean, no raw passphrase)                                                            │
└─────────────────┴──────────────────────────────────────────────────────────┴──────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
Updates needed:
- Ruby: Expand state enum, rename secret_shortkey, add 8 boolean flags, add all timestamp fields, add computed fields
- Spec: Add shortid, receipt_ttl, all boolean flags, computed/derived fields section

---

## V1 Dump Field Analysis (2026-01-29)

**Source:** `exports/metadata/metadata_dump.jsonl`
**Total Records:** 2,428 metadata objects

### V1 Metadata/Receipt Fields (19 fields)

| Field | Description |
|-------|-------------|
| `burned` | Timestamp when the secret was burned (destroyed by owner) |
| `created` | Creation timestamp (epoch float as string) |
| `custid` | Customer identifier (email address or "anon") |
| `key` | The secret key this receipt tracks (primary reference) |
| `lifespan` | TTL duration that was set when created |
| `memo` | Optional memo/subject for incoming secrets |
| `passphrase` | Passphrase indicator/value (if set) |
| `received` | Timestamp when secret was revealed |
| `recipients` | Comma-separated recipient emails |
| `secret_key` | Full secret key reference |
| `secret_shortkey` | Short version of secret key for display (first 8 chars) |
| `secret_ttl` | Time-to-live in seconds for the secret |
| `share_domain` | Custom domain FQDN used for sharing |
| `shared` | Timestamp when secret was shared |
| `state` | Lifecycle state (new, viewed, received, burned) |
| `token` | Receipt token/identifier |
| `truncate` | Truncation indicator |
| `updated` | Last update timestamp (epoch float as string) |
| `viewed` | Timestamp when secret was previewed (by owner) |

### V1 Schema Gaps

The existing V1 schema at `migrations/2026-01-28/lib/schemas/v1/metadata.rb` is missing
several fields that exist in the actual dump data:
- `burned`
- `secret_shortkey`
- `secret_ttl`
- `shared`
- `token`
- `truncate`

### V1 → V2 Migration Notes

1. **Model rename:** Metadata → Receipt
2. **custid → owner_id:** Maps to Customer objid via lookup ("anon" → null)
3. **share_domain → domain_id:** Maps to CustomDomain objid via lookup
4. **key:** Preserved for audit, used to generate deterministic objid
5. **Timestamps:** All lifecycle timestamps (viewed, shared, received, burned) preserved

---

## Model Introspection Comparison (2026-01-29)

### Schema Fields (V2 migration schema) - 20 fields
```
objid, extid, key, owner_id, org_id, domain_id, v1_custid, v1_identifier,
migration_status, migrated_at, state, secret_shortkey, recipients, created,
updated, passphrase_temp, share_domain, ttl, view_count, received
```

### Model Fields (Onetime::Receipt) - 30 fields
```
objid, created, updated, key, viewed, received, shared, burned, custid,
truncate, secret_key, previewed, revealed, v1_identifier, migration_status,
migrated_at, v1_key, v1_custid, owner_id, state, secret_identifier,
secret_shortid, secret_ttl, lifespan, share_domain, passphrase, org_id,
domain_id, recipients, memo
```

### Discrepancies

**In Schema but MISSING from Model (5 fields):**

| Field | Notes |
|-------|-------|
| `extid` | External identifier for URLs (likely computed or inherited) |
| `secret_shortkey` | Model uses `secret_shortid` instead (naming mismatch) |
| `passphrase_temp` | Model uses `passphrase` instead (naming mismatch) |
| `ttl` | Model uses `secret_ttl` and `lifespan` instead (naming mismatch) |
| `view_count` | Not in model fields |

**In Model but MISSING from Schema (15 fields):**

| Field | Notes |
|-------|-------|
| `viewed` | Timestamp when secret was previewed |
| `shared` | Timestamp when secret was shared |
| `burned` | Timestamp when secret was burned |
| `custid` | Legacy customer ID |
| `truncate` | Truncation flag |
| `secret_key` | The actual secret key reference |
| `previewed` | Timestamp when previewed |
| `revealed` | Timestamp when revealed |
| `v1_key` | Migration audit field |
| `secret_identifier` | Full secret identifier |
| `secret_shortid` | Schema has `secret_shortkey` (naming mismatch) |
| `secret_ttl` | Schema has `ttl` (naming mismatch) |
| `lifespan` | Duration field |
| `passphrase` | Schema has `passphrase_temp` (naming mismatch) |
| `memo` | User note field |

### Key Naming Mismatches

| Schema Field | Model Field | Notes |
|--------------|-------------|-------|
| `secret_shortkey` | `secret_shortid` | Schema should use `secret_shortid` |
| `passphrase_temp` | `passphrase` | Schema should use `passphrase` |
| `ttl` | `secret_ttl` | Schema should use `secret_ttl` |
| — | `lifespan` | Model has both `secret_ttl` and `lifespan` |

### Missing Timestamp Fields

The schema lacks all lifecycle timestamp fields that exist in both V1 dump and V2 model:
- `viewed` - when owner previewed
- `shared` - when secret was shared
- `burned` - when owner burned/destroyed
- `previewed` - similar to viewed
- `revealed` - when recipient revealed

**Summary:** The schema has significant naming mismatches and is missing 15 fields
from the actual model. The V1 dump also contains 6 fields not in the V1 schema.
