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
      # V2 uses Familia's JSON serialization, so field values are stored as JSON
      # primitives in Redis. When deserialized, they become native Ruby/JSON types:
      # - Booleans: true/false (not strings "true"/"false")
      # - Numbers: integers and floats (not string representations)
      # - Strings: regular strings
      #
      # The Zod schema in src/schemas/models/receipt.ts is the source of truth
      # for frontend field expectations.
      #
      RECEIPT = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Receipt V2',
        'description' => 'V2 receipt record with JSON-serialized field values',
        'type' => 'object',
        'required' => %w[objid key state migration_status migrated_at],
        'properties' => {
          # === Identity Fields ===

          # Primary identifier (UUIDv7)
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URL paths (matches Zod: extid)
          'extid' => {
            'type' => 'string',
            'pattern' => '^rc[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Short ID for display (matches Zod: shortid)
          'shortid' => {
            'type' => 'string',
            'description' => 'Short identifier for display',
          },

          # Secret key this receipt tracks (matches Zod: key)
          'key' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Secret key this receipt tracks',
          },

          # Short version of secret key (matches Zod: secret_shortid)
          'secret_shortid' => {
            'type' => 'string',
            'description' => 'Short version of secret key for display',
          },

          # Token for receipt access
          'token' => {
            'type' => 'string',
            'description' => 'Receipt access token',
          },

          # === Ownership & Context ===

          # Owner customer objid (resolved from custid)
          'owner_id' => {
            'type' => ['string', 'null'],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid (resolved from customer email)
          'org_id' => {
            'type' => ['string', 'null'],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # Custom domain objid (resolved from share_domain if present)
          'domain_id' => {
            'type' => ['string', 'null'],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Custom domain objid (UUIDv7, optional)',
          },

          # Custom domain FQDN (preserved for context)
          'share_domain' => {
            'type' => ['string', 'null'],
            'description' => 'Custom domain FQDN used for sharing',
          },

          # Recipients (comma-separated emails)
          'recipients' => {
            'type' => ['string', 'null'],
            'description' => 'Comma-separated recipient emails',
          },

          # === State & Lifecycle (matches Zod: state enum) ===

          # Lifecycle state
          'state' => {
            'type' => 'string',
            'enum' => %w[new shared viewed received burned revealed previewed expired orphaned],
            'description' => 'Receipt/secret lifecycle state',
          },

          # Secret state (separate from receipt state)
          'secret_state' => {
            'type' => ['string', 'null'],
            'enum' => %w[new viewed received burned],
            'description' => 'Secret lifecycle state',
          },

          # === Boolean Flags (matches Zod: is_* fields) ===

          'is_viewed' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been viewed',
          },
          'is_received' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been received',
          },
          'is_previewed' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been previewed by owner',
          },
          'is_revealed' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been revealed',
          },
          'is_burned' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been burned',
          },
          'is_destroyed' => {
            'type' => 'boolean',
            'description' => 'Whether secret has been destroyed',
          },
          'is_expired' => {
            'type' => 'boolean',
            'description' => 'Whether secret has expired',
          },
          'is_orphaned' => {
            'type' => 'boolean',
            'description' => 'Whether secret is orphaned (owner deleted)',
          },
          'has_passphrase' => {
            'type' => 'boolean',
            'description' => 'Whether secret requires a passphrase',
          },
          'truncate' => {
            'type' => 'boolean',
            'description' => 'Whether content was truncated',
          },

          # === Numeric Fields ===

          # TTL in seconds - INTEGER
          'ttl' => {
            'type' => 'integer',
            'minimum' => 0,
            'description' => 'Time-to-live in seconds',
          },

          # Secret TTL in seconds - INTEGER
          'secret_ttl' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'Secret time-to-live in seconds',
          },

          # Receipt TTL in seconds - INTEGER
          'receipt_ttl' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'Receipt time-to-live in seconds',
          },

          # Lifespan in seconds - INTEGER
          'lifespan' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'TTL duration in seconds (V1 field name)',
          },

          # View count - INTEGER
          'view_count' => {
            'type' => 'integer',
            'minimum' => 0,
            'description' => 'Number of times viewed',
          },

          # === Timestamps (as numbers) ===

          # Creation timestamp - NUMBER
          'created' => {
            'type' => 'number',
            'description' => 'Creation timestamp (Unix epoch)',
          },

          # Last update timestamp - NUMBER
          'updated' => {
            'type' => 'number',
            'description' => 'Last update timestamp (Unix epoch)',
          },

          # Shared timestamp - NUMBER (nullable)
          'shared' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was shared',
          },

          # Viewed timestamp - NUMBER (nullable)
          'viewed' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was previewed by owner',
          },

          # Previewed timestamp - NUMBER (nullable)
          'previewed' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was previewed',
          },

          # Revealed timestamp - NUMBER (nullable)
          'revealed' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was revealed',
          },

          # Received timestamp - NUMBER (nullable)
          'received' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was received',
          },

          # Burned timestamp - NUMBER (nullable)
          'burned' => {
            'type' => ['number', 'null'],
            'description' => 'Timestamp when secret was burned',
          },

          # Natural expiration timestamp - NUMBER (nullable)
          'natural_expiration' => {
            'type' => ['number', 'null'],
            'description' => 'Natural expiration timestamp',
          },

          # Expiration timestamp - NUMBER (nullable)
          'expiration' => {
            'type' => ['number', 'null'],
            'description' => 'Expiration timestamp',
          },

          # Expiration in seconds - INTEGER (nullable)
          'expiration_in_seconds' => {
            'type' => ['integer', 'null'],
            'description' => 'Seconds until expiration',
          },

          # === Content Fields ===

          # Optional memo/subject
          'memo' => {
            'type' => ['string', 'null'],
            'description' => 'Optional memo or subject',
          },

          # Full secret key reference
          'secret_key' => {
            'type' => ['string', 'null'],
            'description' => 'Full secret key reference',
          },

          # Passphrase indicator (backend-only, not exposed)
          'passphrase' => {
            'type' => ['string', 'null'],
            'description' => 'Passphrase hash (backend-only)',
          },

          # Temporary passphrase indicator
          'passphrase_temp' => {
            'type' => ['string', 'null'],
            'description' => 'Temporary passphrase indicator',
          },

          # === Migration Tracking ===

          # Original V1 custid (email) preserved for audit
          'v1_custid' => {
            'type' => ['string', 'null'],
            'description' => 'Original V1 customer identifier (email)',
          },

          # Original V1 Redis key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^metadata:.+:object$',
            'description' => 'Original V1 Redis key',
          },

          # Migration status
          'migration_status' => {
            'type' => 'string',
            'enum' => %w[pending completed failed],
            'description' => 'Migration status',
          },

          # Migration timestamp - NUMBER
          'migrated_at' => {
            'type' => 'number',
            'description' => 'Migration timestamp (Unix epoch float)',
          },

          # === Deprecated Fields ===

          # V1 field name for secret_shortid
          'secret_shortkey' => {
            'type' => 'string',
            'description' => 'Deprecated: Use secret_shortid instead',
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
