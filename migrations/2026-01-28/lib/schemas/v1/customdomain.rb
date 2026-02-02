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

          # V1 identifier (20-char hex)
          'key' => {
            'type' => 'string',
            'description' => 'V1 identifier (20-char hex)',
          },

          # Same as key (aliased)
          'domainid' => {
            'type' => 'string',
            'description' => 'Domain ID (alias of key)',
          },

          # Original input value
          '_original_value' => {
            'type' => 'string',
            'description' => 'Original input value before normalization',
          },

          # JSON blob from Approximated API
          'vhost' => {
            'type' => 'string',
            'description' => 'JSON blob from Approximated API',
          },

          # Domain status
          'status' => {
            'type' => 'string',
            'description' => 'Domain status',
          },

          # DNS resolving flag
          'resolving' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'DNS resolving status',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # JSON Schema for V1 customdomain brand data (stored as separate Redis hash).
      CUSTOMDOMAIN_BRAND = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain Brand V1',
        'description' => 'V1 customdomain brand settings from Redis hash',
        'type' => 'object',
        'properties' => {
          'primary_color' => {
            'type' => 'string',
            'description' => 'Brand primary color (hex)',
          },
          'font_family' => {
            'type' => 'string',
            'enum' => %w[sans mono serif],
            'description' => 'Font family (sans, mono, serif)',
          },
          'corner_style' => {
            'type' => 'string',
            'enum' => %w[rounded square pill],
            'description' => 'Corner style (rounded, square, pill)',
          },
          'button_text_light' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Use light button text',
          },
          'instructions_pre_reveal' => {
            'type' => 'string',
            'description' => 'Text shown before reveal',
          },
          'instructions_post_reveal' => {
            'type' => 'string',
            'description' => 'Text shown after reveal',
          },
          'locale' => {
            'type' => 'string',
            'description' => 'Language locale (e.g., en)',
          },
          'allow_public_homepage' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Allow public homepage',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # JSON Schema for V1 customdomain logo data (stored as separate Redis hash).
      CUSTOMDOMAIN_LOGO = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain Logo V1',
        'description' => 'V1 customdomain logo data from Redis hash',
        'type' => 'object',
        'properties' => {
          'filename' => {
            'type' => 'string',
            'description' => 'Original filename',
          },
          'content_type' => {
            'type' => 'string',
            'description' => 'MIME type (e.g., image/jpeg)',
          },
          'ratio' => {
            'type' => 'string',
            'description' => 'Aspect ratio',
          },
          'width' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Image width in pixels',
          },
          'height' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Image height in pixels',
          },
          'encoded' => {
            'type' => 'string',
            'description' => 'Base64-encoded image data',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schemas
      Schemas.register(:customdomain_v1, CUSTOMDOMAIN)
      Schemas.register(:customdomain_brand_v1, CUSTOMDOMAIN_BRAND)
      Schemas.register(:customdomain_logo_v1, CUSTOMDOMAIN_LOGO)
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
