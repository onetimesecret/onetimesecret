# migrations/2026-01-28/lib/schemas/v2/customdomain.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 customdomain data (output after transformation).
      #
      # V2 customdomains use UUIDv7 objid as identifier, have extid for URLs,
      # reference owner (customer) and organization via objids,
      # and include migration tracking fields.
      #
      CUSTOMDOMAIN = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain V2',
        'description' => 'V2 customdomain record after migration transformation',
        'type' => 'object',
        'required' => %w[objid display_domain owner_id migration_status migrated_at],
        'properties' => {
          # New primary identifier (UUIDv7)
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URLs
          'extid' => {
            'type' => 'string',
            'pattern' => '^cd[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Domain display name (e.g., "example.com")
          'display_domain' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Display domain name (FQDN)',
          },

          # Base domain
          'base_domain' => {
            'type' => 'string',
            'description' => 'Base domain (e.g., "example.com")',
          },

          # Subdomain component
          'subdomain' => {
            'type' => 'string',
            'description' => 'Subdomain component (e.g., "www")',
          },

          # Third-level domain
          'trd' => {
            'type' => 'string',
            'description' => 'Third-level domain component',
          },

          # Top-level domain
          'tld' => {
            'type' => 'string',
            'description' => 'Top-level domain (e.g., "com", "org")',
          },

          # Second-level domain
          'sld' => {
            'type' => 'string',
            'description' => 'Second-level domain (e.g., "example")',
          },

          # Owner customer objid (UUIDv7)
          'owner_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid (UUIDv7)
          'org_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # Original V1 custid (email) preserved for reference
          'v1_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer identifier (email)',
          },

          # Original V1 key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^customdomain:.+:object$',
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

          # TXT validation fields
          'txt_validation_value' => {
            'type' => 'string',
            'description' => 'TXT record validation value',
          },
          'txt_validation_host' => {
            'type' => 'string',
            'description' => 'TXT record validation host',
          },

          # Verification status fields
          'verification_status' => {
            'type' => 'string',
            'enum' => %w[pending verified failed],
            'description' => 'Domain verification status',
          },
          'verified' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Domain verified flag',
          },
          'verified_at' => {
            'type' => 'string',
            'pattern' => '^\\d+(\\.\\d+)?$',
            'description' => 'Verification timestamp (epoch float as string)',
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

          # Active status
          'active' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Domain active status',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:customdomain_v2, CUSTOMDOMAIN)
    end
  end
end

__END__

## Source Files
- Ruby Schema: migrations/2026-01-28/lib/schemas/v2/customdomain.rb
- Spec.md: migrations/2026-01-26/03-customdomain/spec.md
- Zod Schema: src/schemas/models/domain/index.ts

---
CustomDomain
┌────────────────┬───────────────────────────────────────┬───────────────────────────────────────────────┬─────────────────────────────┐
│    Category    │              Ruby Schema              │                    Spec.md                    │         Zod (truth)         │
├────────────────┼───────────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────┤
│ Base fields    │ Missing: identifier, domainid, custid │ Missing: identifier, _original_value, is_apex │ Has all                     │
├────────────────┼───────────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────┤
│ Nested objects │ Missing: vhost, brand                 │ Has vhost, brand as related data              │ Has both as nullable nested │
├────────────────┼───────────────────────────────────────┼───────────────────────────────────────────────┼─────────────────────────────┤
│ Backend-only   │ owner_id, org_id, verification_status │ Same                                          │ Not exposed                 │
└────────────────┴───────────────────────────────────────┴───────────────────────────────────────────────┴─────────────────────────────┘
Updates needed:
- Ruby: Add identifier, domainid, custid, _original_value, is_apex, nested objects
- Spec: Add identifier, _original_value, is_apex; clarify custid is nullable (not removed)

---

## V1 Dump Field Analysis (2026-01-29)

**Source:** `exports/customdomain/customdomain_dump.jsonl`
**Total Records:** 14 customdomain objects, 12 brand records, 10 logo records

### V1 CustomDomain `:object` Fields (18 fields)

| Field | Description |
|-------|-------------|
| `key` | V1 identifier (20-char hex) |
| `domainid` | Same as key (aliased) |
| `custid` | Customer email (v1 FK) |
| `display_domain` | Full domain name (e.g., secrets.example.com) |
| `base_domain` | Root domain (e.g., example.com) |
| `subdomain` | Full subdomain (e.g., secrets.example.com) |
| `trd` | Transit routing domain (e.g., secrets) |
| `sld` | Second-level domain (e.g., example) |
| `tld` | Top-level domain (e.g., com) |
| `_original_value` | Original input value |
| `txt_validation_host` | TXT record hostname for verification |
| `txt_validation_value` | TXT record value (32-char hex) |
| `vhost` | JSON blob from Approximated API |
| `status` | Domain status |
| `verified` | TXT record verified (true/false) |
| `resolving` | DNS resolving (true/false) |
| `created` | Unix timestamp |
| `updated` | Unix timestamp |

### V1 CustomDomain `:brand` Fields (8 fields)

| Field | Description |
|-------|-------------|
| `primary_color` | Brand color |
| `font_family` | Font family (sans, mono, etc.) |
| `corner_style` | Corner style (rounded, square, pill) |
| `button_text_light` | Button text color setting |
| `instructions_pre_reveal` | Text shown before reveal |
| `instructions_post_reveal` | Text shown after reveal |
| `locale` | Language locale (e.g., en) |
| `allow_public_homepage` | Boolean flag |

### V1 CustomDomain `:logo` Fields (6 fields)

| Field | Description |
|-------|-------------|
| `filename` | Original filename |
| `content_type` | MIME type (e.g., image/jpeg) |
| `ratio` | Aspect ratio |
| `width` | Image width in pixels |
| `height` | Image height in pixels |
| `encoded` | Base64-encoded image data |

### V1 → V2 Migration Notes

1. **custid → org_id:** V1 uses customer email, V2 uses organization objid
2. **key/domainid → objid:** V2 uses UUIDv7-based objid with extid format `cd%<id>s`
3. **Nested hashkeys:** brand and logo are stored as separate Redis hash keys in both versions
4. **vhost:** Contains JSON blob from external API, preserved as-is

---

## Model Introspection Comparison (2026-01-29)

### Schema Fields (V2 migration schema) - ~18 fields
```
objid, extid, display_domain, base_domain, subdomain, trd, tld, sld,
owner_id, org_id, v1_custid, v1_identifier, migration_status, migrated_at,
txt_validation_value, txt_validation_host, verification_status, verified,
verified_at, created, updated, active
```

### Model Fields (Onetime::CustomDomain) - 22 fields
```
objid, extid, v1_identifier, migration_status, migrated_at, v1_custid,
display_domain, org_id, base_domain, subdomain, trd, tld, sld,
txt_validation_host, txt_validation_value, status, vhost, verified,
resolving, created, updated, _original_value
```

### Discrepancies

**In Model but MISSING from Schema (4 fields):**

| Field | Type | Notes |
|-------|------|-------|
| `status` | field | General status field (distinct from verification_status) |
| `vhost` | field | Virtual host reference (JSON blob) |
| `resolving` | field | DNS resolving status |
| `_original_value` | field | Internal tracking field |

**In Schema but MISSING from Model (4 fields):**

| Field | Notes |
|-------|-------|
| `owner_id` | Schema has it, model doesn't (may derive from org_id) |
| `verification_status` | Schema defines enum; model has `status` instead |
| `verified_at` | Verification timestamp |
| `active` | Active status flag |

**Related Collections (model only):**
- `participations` (UnsortedSet)
- `receipts` (SortedSet)

### Key Observations

1. **owner_id mismatch:** Schema expects owner_id but model doesn't define it. May be derived from org_id lookup.
2. **Status fields:** Model has `status` and `resolving`, schema has `verification_status` and `active`. Different aspects of domain state.
3. **vhost representation:** Model has it as a field (JSON blob), schema doesn't include it.
4. **_original_value:** Model has this internal field; schema doesn't (probably intentional for internal tracking).
