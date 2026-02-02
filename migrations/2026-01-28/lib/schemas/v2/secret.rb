# migrations/2026-01-28/lib/schemas/v2/secret.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 secret data (output after transformation).
      #
      # V2 secrets use UUIDv7 objid, have extid for URLs,
      # link to owner/org via lookups, and include migration tracking fields.
      #
      # CRITICAL: The value field must be preserved EXACTLY as-is during migration.
      #
      # V2 uses Familia's JSON serialization, so field values are stored as JSON
      # primitives in Redis. When deserialized, they become native Ruby/JSON types:
      # - Booleans: true/false (not strings "true"/"false")
      # - Numbers: integers and floats (not string representations)
      # - Strings: regular strings
      #
      # The Zod schema in src/schemas/models/secret.ts is the source of truth
      # for frontend field expectations.
      #
      SECRET = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Secret V2',
        'description' => 'V2 secret record with JSON-serialized field values',
        'type' => 'object',
        'required' => %w[objid value state migration_status migrated_at],
        'properties' => {
          # === Identity Fields ===

          # Primary identifier (UUIDv7) - frontend uses 'identifier'
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URLs
          'extid' => {
            'type' => 'string',
            'pattern' => '^se[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Secret key (V1 identifier preserved)
          'key' => {
            'type' => 'string',
            'description' => 'Secret identifier key',
          },

          # Short ID for display (matches Zod: shortid)
          'shortid' => {
            'type' => 'string',
            'description' => 'Short identifier for display',
          },

          # Access token
          'token' => {
            'type' => 'string',
            'description' => 'Access token for secret',
          },

          # === Ownership (nullable for anonymous secrets) ===

          # Owner customer objid
          'owner_id' => {
            'type' => ['string', 'null'],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid
          'org_id' => {
            'type' => ['string', 'null'],
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # V1 custid (email or "anon")
          'custid' => {
            'type' => ['string', 'null'],
            'description' => 'V1 customer ID (email or "anon")',
          },

          # === Content (CRITICAL - preserved exactly) ===

          # Encrypted value - MUST be preserved exactly from V1
          'value' => {
            'type' => 'string',
            'description' => 'Encrypted secret content (preserved exactly)',
          },

          # Checksum of the value
          'value_checksum' => {
            'type' => ['string', 'null'],
            'description' => 'SHA checksum of the encrypted value',
          },

          # Encryption version
          'value_encryption' => {
            'type' => ['string', 'null'],
            'description' => 'Encryption version (e.g., "2")',
          },

          # Original size before truncation - INTEGER
          'original_size' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'Original size in bytes before truncation',
          },

          # Whether content was truncated - BOOLEAN
          'truncated' => {
            'type' => 'boolean',
            'description' => 'Whether content was truncated',
          },

          # === State & Security ===

          # Secret state (matches Zod: state enum with all values)
          'state' => {
            'type' => 'string',
            'enum' => %w[new viewed received burned revealed previewed],
            'description' => 'Secret lifecycle state',
          },

          # Whether secret has a passphrase - BOOLEAN (matches Zod: has_passphrase)
          'has_passphrase' => {
            'type' => 'boolean',
            'description' => 'Whether secret is passphrase protected',
          },

          # Passphrase hash (backend-only)
          'passphrase' => {
            'type' => ['string', 'null'],
            'description' => 'Encrypted passphrase hash (backend-only)',
          },

          # Passphrase encryption algorithm - INTEGER
          'passphrase_encryption' => {
            'type' => ['integer', 'null'],
            'enum' => [1, 2],
            'description' => 'Passphrase encryption algorithm (1=bcrypt, 2=argon2)',
          },

          # Verification status
          'verification' => {
            'type' => ['string', 'null'],
            'description' => 'Verification status',
          },

          # === TTL & Lifespan (as integers) ===

          # TTL in seconds - INTEGER
          'secret_ttl' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'Secret TTL in seconds',
          },

          # Lifespan in seconds (V1 field name) - INTEGER
          'lifespan' => {
            'type' => ['integer', 'null'],
            'minimum' => 0,
            'description' => 'TTL in seconds (V1 field name)',
          },

          # Maximum views allowed - INTEGER
          'maxviews' => {
            'type' => ['integer', 'null'],
            'minimum' => 1,
            'description' => 'Maximum allowed views',
          },

          # === Sharing Context ===

          # Recipient email
          'recipient' => {
            'type' => ['string', 'null'],
            'description' => 'Recipient email address',
          },

          # Custom domain for sharing
          'share_domain' => {
            'type' => ['string', 'null'],
            'description' => 'Custom domain FQDN for sharing',
          },

          # Metadata/Receipt key reference
          'metadata_key' => {
            'type' => ['string', 'null'],
            'description' => 'Reference to associated receipt record',
          },

          # Receipt identifier
          'receipt_identifier' => {
            'type' => ['string', 'null'],
            'description' => 'Associated receipt identifier',
          },

          # Receipt short ID
          'receipt_shortid' => {
            'type' => ['string', 'null'],
            'description' => 'Short receipt ID for display',
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

          # === Migration Tracking ===

          # Original V1 Redis key
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^secret:.+:object$',
            'description' => 'Original V1 Redis key',
          },

          # V1 custid preserved
          'v1_custid' => {
            'type' => ['string', 'null'],
            'description' => 'Original V1 customer ID',
          },

          # V1 original size
          'v1_original_size' => {
            'type' => ['integer', 'null'],
            'description' => 'V1 original size tracking',
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
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:secret_v2, SECRET)
    end
  end
end


__END__

## Source Files
- Ruby Schema: migrations/2026-01-28/lib/schemas/v2/secret.rb
- Spec.md: migrations/2026-01-26/05-secret/spec.md
- Zod Schema: src/schemas/models/secret.ts

---
Secret
┌────────────────┬─────────────────────────────────────────────────────────────────┬─────────────────────┬─────────────────────────────────┐
│    Category    │                           Ruby Schema                           │       Spec.md       │           Zod (truth)           │
├────────────────┼─────────────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────────────────┤
│ Field renames  │ objid→identifier, passphrase→has_passphrase, value→secret_value │ Uses objid          │ Uses identifier, has_passphrase │
├────────────────┼─────────────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────────────────┤
│ State enum     │ Missing: revealed, previewed                                    │ Documents transform │ Has all 6 values                │
├────────────────┼─────────────────────────────────────────────────────────────────┼─────────────────────┼─────────────────────────────────┤
│ Missing fields │ key, shortid, verification, lifespan                            │ —                   │ Has all                         │
└────────────────┴─────────────────────────────────────────────────────────────────┴─────────────────────┴─────────────────────────────────┘
Updates needed:
- Ruby: Rename 3 fields, add 4 fields, expand state enum
- Spec: Clarify identifier is the frontend field name

---

## V1 Dump Field Analysis (2026-01-29)

**Source:** `exports/secret/secret_dump.jsonl`
**Total Records:** 603 secret objects

### V1 Secret Fields (18 fields)

| Field | Description |
|-------|-------------|
| `created` | Unix timestamp of creation |
| `custid` | Customer ID (e.g., "anon" or email) |
| `key` | Secret identifier/key |
| `lifespan` | TTL in seconds (e.g., 604800 = 7 days) |
| `maxviews` | Maximum allowed views (typically 1) |
| `metadata_key` | Reference to associated metadata record |
| `original_size` | Original size before truncation |
| `passphrase` | Encrypted passphrase (bcrypt hash) |
| `passphrase_encryption` | Encryption flag for passphrase |
| `share_domain` | Custom domain for sharing |
| `state` | State (e.g., "new", "viewed") |
| `token` | Access token |
| `truncated` | Truncation flag |
| `updated` | Unix timestamp of last update |
| `value` | Encrypted secret content |
| `value_checksum` | SHA checksum of the value |
| `value_encryption` | Encryption version (e.g., "2") |
| `verification` | Verification status |

### V1 → V2 Migration Notes

1. **custid:** Maps to owner_id (UUIDv7) via customer lookup
2. **metadata_key:** Links to Receipt (formerly Metadata) record
3. **value:** CRITICAL - must be preserved exactly as-is during migration
4. **key:** Becomes part of v1_identifier for audit trail

---

## Model Introspection Comparison (2026-01-29)

### Schema Fields (V2 migration schema) - 16 fields
```
objid, extid, owner_id, org_id, value, value_checksum, state, secret_ttl,
passphrase, created, updated, recipient, share_domain, v1_identifier,
migration_status, migrated_at
```

### Model Fields (Onetime::Secret) - 26 fields
```
objid, created, updated, passphrase, passphrase_encryption, value, value_encryption,
share_domain, verification, custid, metadata_key, truncated, secret_key, v1_identifier,
migration_status, migrated_at, v1_custid, v1_original_size, state, lifespan,
receipt_identifier, receipt_shortid, owner_id, ciphertext, ciphertext_passphrase,
ciphertext_domain
```

### Discrepancies

**In schema but MISSING from model (5 fields):**

| Field | Notes |
|-------|-------|
| `extid` | External identifier for URLs (likely computed or inherited) |
| `org_id` | Organization reference |
| `value_checksum` | Integrity check |
| `secret_ttl` | TTL in seconds |
| `recipient` | Email address |

**In model but MISSING from schema (15 fields):**

| Field | Notes |
|-------|-------|
| `passphrase_encryption` | Encryption method for passphrase |
| `value_encryption` | Encryption method for value |
| `verification` | Verification flag |
| `custid` | Legacy customer ID |
| `metadata_key` | Link to metadata/receipt record |
| `truncated` | Truncation flag |
| `secret_key` | Secret key reference |
| `v1_custid` | V1 customer ID (migration) |
| `v1_original_size` | V1 size tracking |
| `lifespan` | Alternative TTL field |
| `receipt_identifier` | Receipt reference |
| `receipt_shortid` | Short receipt ID |
| `ciphertext` | Encrypted content |
| `ciphertext_passphrase` | Encrypted passphrase |
| `ciphertext_domain` | Encrypted domain |

**Summary:** The schema is significantly incomplete compared to the actual model.
The model has 26 fields while the schema only documents 16, and there are 5
schema fields not present in the model at all.
