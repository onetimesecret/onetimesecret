# migrations/2026-01-28/lib/schemas/v1/customdomain.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V1
      # JSON Schema for V1 customdomain data (input from Redis HGETALL).
      #
      # V1 customdomains use display_domain as identifier and store fields as Redis hash.
      # All values are strings since Redis hashes only store strings.
      #
      CUSTOMDOMAIN = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain V1',
        'description' => 'V1 customdomain record from Redis hash (pre-migration)',
        'type' => 'object',
        'required' => %w[display_domain custid],
        'properties' => {
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

          # Customer identifier (email in V1)
          'custid' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Customer identifier (email address in V1)',
          },

          # TXT validation value
          'txt_validation_value' => {
            'type' => 'string',
            'description' => 'TXT record validation value',
          },

          # TXT validation host
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

          # Timestamps (stored as epoch floats as strings)
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
      Schemas.register(:customdomain_v1, CUSTOMDOMAIN)
    end
  end
end

__END__

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

### V1 Schema Coverage

**Schema has 16 fields. Dump `:object` has 18 fields + 14 nested fields.**

**In schema (16):** `display_domain`, `base_domain`, `subdomain`, `trd`, `tld`, `sld`, `custid`, `txt_validation_value`, `txt_validation_host`, `verification_status`, `verified`, `verified_at`, `created`, `updated`, `active`

**Missing from schema (6 + nested):**
- `key` - V1 identifier (20-char hex)
- `domainid` - Same as key (aliased)
- `_original_value` - Original input value
- `vhost` - JSON blob from Approximated API
- `status` - Domain status
- `resolving` - DNS resolving flag
- `:brand` hash (8 fields) - stored as separate Redis hash
- `:logo` hash (6 fields) - stored as separate Redis hash
