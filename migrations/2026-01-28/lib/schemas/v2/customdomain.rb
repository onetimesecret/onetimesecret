# migrations/2026-01-28/lib/schemas/v2/customdomain.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 customdomain data (output after transformation).
      #
      # V2 uses Familia's JSON serialization, so field values are stored as JSON
      # primitives in Redis. When deserialized, they become native Ruby/JSON types:
      # - Booleans: true/false (not strings "true"/"false")
      # - Numbers: integers and floats (not string representations)
      # - Strings: regular strings
      # - Objects: nested hashes (for vhost, brand)
      #
      # The Zod schema in src/schemas/models/domain/index.ts is the source of truth
      # for frontend field expectations.
      #
      CUSTOMDOMAIN = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain V2',
        'description' => 'V2 customdomain record with JSON-serialized field values',
        'type' => 'object',
        'required' => %w[objid display_domain org_id migration_status migrated_at],
        'properties' => {
          # === Identity Fields ===

          # Primary identifier (UUIDv7)
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URLs (matches Zod: extid)
          'extid' => {
            'type' => 'string',
            'pattern' => '^cd[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # V1 identifier preserved for backwards compatibility (matches Zod: domainid)
          'domainid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{20}$',
            'description' => 'V1 domain identifier (20-char hex)',
          },

          # Alias for domainid (V1 legacy)
          'key' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{20}$',
            'description' => 'V1 key (alias of domainid)',
          },

          # === Domain Name Components ===

          # Full domain name (matches Zod: display_domain)
          'display_domain' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Full domain name (e.g., "secrets.example.com")',
          },

          # Root domain (matches Zod: base_domain)
          'base_domain' => {
            'type' => 'string',
            'description' => 'Base domain (e.g., "example.com")',
          },

          # Subdomain component (matches Zod: subdomain)
          'subdomain' => {
            'type' => 'string',
            'description' => 'Subdomain (e.g., "secrets.example.com")',
          },

          # Third-level domain (matches Zod: trd)
          'trd' => {
            'type' => 'string',
            'description' => 'Third-level domain component (e.g., "secrets")',
          },

          # Top-level domain (matches Zod: tld)
          'tld' => {
            'type' => 'string',
            'description' => 'Top-level domain (e.g., "com")',
          },

          # Second-level domain (matches Zod: sld)
          'sld' => {
            'type' => 'string',
            'description' => 'Second-level domain (e.g., "example")',
          },

          # Original input value before normalization (matches Zod: _original_value)
          '_original_value' => {
            'type' => 'string',
            'description' => 'Original user input before domain normalization',
          },

          # Whether domain is apex (no subdomain) (matches Zod: is_apex)
          'is_apex' => {
            'type' => 'boolean',
            'description' => 'True if this is an apex domain (no subdomain)',
          },

          # === Ownership Fields ===

          # Organization objid (UUIDv7) - V2 primary reference
          'org_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # V1 customer email - nullable for V2-native domains (matches Zod: custid)
          'custid' => {
            'type' => ['string', 'null'],
            'description' => 'V1 customer identifier (email) - null for V2-native domains',
          },

          # === Verification Fields ===

          # TXT record validation host (matches Zod: txt_validation_host)
          'txt_validation_host' => {
            'type' => 'string',
            'description' => 'TXT record hostname for verification',
          },

          # TXT record validation value (matches Zod: txt_validation_value)
          'txt_validation_value' => {
            'type' => 'string',
            'description' => 'TXT record value (32-char hex)',
          },

          # TXT record verified (matches Zod: verified - boolean)
          'verified' => {
            'type' => 'boolean',
            'description' => 'Whether TXT record has been verified',
          },

          # DNS is resolving (model field, not in Zod - backend only)
          'resolving' => {
            'type' => 'boolean',
            'description' => 'Whether domain DNS is resolving',
          },

          # Domain status string (model field)
          'status' => {
            'type' => 'string',
            'description' => 'Domain status (e.g., "active", "pending")',
          },

          # === Virtual Host (Approximated API) ===

          # VHost data from Approximated API (matches Zod: vhost - nullable object)
          'vhost' => {
            'type' => ['object', 'null'],
            'description' => 'Virtual host data from Approximated API',
            'properties' => {
              'id' => { 'type' => 'integer' },
              'status' => { 'type' => 'string' },
              'incoming_address' => { 'type' => 'string' },
              'target_address' => { 'type' => 'string' },
              'target_ports' => { 'type' => 'string' },
              'apx_hit' => { 'type' => 'boolean' },
              'has_ssl' => { 'type' => 'boolean' },
              'is_resolving' => { 'type' => 'boolean' },
              'created_at' => { 'type' => 'string' },
              'last_monitored_unix' => { 'type' => 'number' },
              'ssl_active_from' => { 'type' => ['string', 'null'] },
              'ssl_active_until' => { 'type' => ['string', 'null'] },
              'dns_pointed_at' => { 'type' => 'string' },
              'keep_host' => { 'type' => ['string', 'null'] },
              'last_monitored_humanized' => { 'type' => 'string' },
              'status_message' => { 'type' => 'string' },
              'user_message' => { 'type' => 'string' },
            },
            'additionalProperties' => true,
          },

          # === Timestamps ===

          # Creation timestamp (epoch seconds as float)
          'created' => {
            'type' => 'number',
            'description' => 'Creation timestamp (Unix epoch float)',
          },

          # Last update timestamp (epoch seconds as float)
          'updated' => {
            'type' => 'number',
            'description' => 'Last update timestamp (Unix epoch float)',
          },

          # === Migration Tracking ===

          # Original V1 Redis key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^customdomain:.+:object$',
            'description' => 'Original V1 Redis key',
          },

          # Original V1 custid preserved for reference
          'v1_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer email',
          },

          # Migration status
          'migration_status' => {
            'type' => 'string',
            'enum' => %w[pending completed failed],
            'description' => 'Migration status',
          },

          # Migration timestamp (epoch seconds as float)
          'migrated_at' => {
            'type' => 'number',
            'description' => 'Migration timestamp (Unix epoch float)',
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
- Zod Schema: src/schemas/models/domain/index.ts (source of truth for frontend)
- Model: lib/onetime/models/custom_domain.rb

---

## V2 Schema Summary (Updated 2026-01-30)

This schema uses **JSON primitives** (not string representations) because Familia v2
uses JSON serialization for Redis hash field values.

### Field Types

| Field | JSON Type | Notes |
|-------|-----------|-------|
| `objid` | string | UUIDv7 format |
| `extid` | string | Format: `cd<base32>` |
| `domainid` | string | V1 20-char hex identifier |
| `key` | string | Alias for domainid |
| `display_domain` | string | Full FQDN |
| `base_domain` | string | Root domain |
| `subdomain` | string | Subdomain portion |
| `trd` | string | Third-level domain |
| `tld` | string | Top-level domain |
| `sld` | string | Second-level domain |
| `_original_value` | string | User input before normalization |
| `is_apex` | **boolean** | True if apex domain |
| `org_id` | string | Organization UUIDv7 |
| `custid` | string/null | V1 customer email (nullable) |
| `txt_validation_host` | string | DNS verification hostname |
| `txt_validation_value` | string | DNS verification value |
| `verified` | **boolean** | TXT record verified |
| `resolving` | **boolean** | DNS is resolving |
| `status` | string | Domain status |
| `vhost` | **object/null** | Approximated API data |
| `created` | **number** | Unix epoch float |
| `updated` | **number** | Unix epoch float |
| `migrated_at` | **number** | Unix epoch float |
| `migration_status` | string | enum: pending/completed/failed |

### Key Differences from V1

1. **Booleans are native**: `verified`, `resolving`, `is_apex` are JSON booleans (true/false), not strings ("true"/"false")
2. **Timestamps are numbers**: `created`, `updated`, `migrated_at` are floats, not strings
3. **vhost is an object**: Parsed JSON object, not a JSON string
4. **custid is nullable**: V2-native domains may not have a V1 customer reference

---

## V1 Dump Field Analysis (2026-01-29)

**Source:** `exports/customdomain/customdomain_dump.jsonl`
**Total Records:** 14 customdomain objects, 12 brand records, 10 logo records

### V1 CustomDomain `:object` Fields (18 fields)

| Field | V1 Type | V2 Type |
|-------|---------|---------|
| `key` | string | string |
| `domainid` | string | string |
| `custid` | string | string/null |
| `display_domain` | string | string |
| `base_domain` | string | string |
| `subdomain` | string | string |
| `trd` | string | string |
| `sld` | string | string |
| `tld` | string | string |
| `_original_value` | string | string |
| `txt_validation_host` | string | string |
| `txt_validation_value` | string | string |
| `vhost` | string (JSON) | object |
| `status` | string | string |
| `verified` | string ("true"/"false") | boolean |
| `resolving` | string ("true"/"false") | boolean |
| `created` | string (epoch) | number |
| `updated` | string (epoch) | number |

### V1 → V2 Type Transformations

1. **Boolean fields** (`verified`, `resolving`): "true"/"false" → true/false
2. **Timestamp fields** (`created`, `updated`): "1234567890" → 1234567890.0
3. **JSON fields** (`vhost`): "{...}" → {...} (parsed object)
4. **custid**: Required string → nullable (null for V2-native domains)
