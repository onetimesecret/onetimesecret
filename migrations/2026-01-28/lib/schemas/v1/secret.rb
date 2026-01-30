# migrations/2026-01-28/lib/schemas/v1/secret.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V1
      # JSON Schema for V1 secret data (input from Redis HGETALL).
      #
      # V1 secrets use a random key identifier and store fields as Redis hash.
      # All values are strings since Redis hashes only store strings.
      #
      SECRET = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Secret V1',
        'description' => 'V1 secret record from Redis hash (pre-migration)',
        'type' => 'object',
        'required' => %w[key],
        'properties' => {
          # Primary identifier (random string in V1)
          'key' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Secret identifier key',
          },

          # Encrypted value (CRITICAL - must be preserved exactly)
          'value' => {
            'type' => 'string',
            'description' => 'Encrypted secret content',
          },

          # Checksum of the value
          'value_checksum' => {
            'type' => 'string',
            'description' => 'Checksum of the encrypted value',
          },

          # Owner customer ID (email in V1, may be absent for anonymous)
          'custid' => {
            'type' => 'string',
            'description' => 'Customer identifier (email address in V1)',
          },

          # Secret state
          'state' => {
            'type' => 'string',
            'enum' => %w[new viewed received burned],
            'description' => 'Secret state',
          },

          # Passphrase (bcrypt hash if set, or indicator)
          'passphrase' => {
            'type' => 'string',
            'description' => 'Encrypted passphrase (bcrypt hash) or indicator',
          },

          # Time to live in seconds
          'secret_ttl' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Secret TTL in seconds (integer as string)',
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

          # Recipient email (optional)
          'recipient' => {
            'type' => 'string',
            'description' => 'Recipient email address',
          },

          # Share domain (optional)
          'share_domain' => {
            'type' => 'string',
            'description' => 'Custom domain for sharing',
          },

          # TTL in seconds (lifespan is V1 field name)
          'lifespan' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'TTL in seconds (V1 field name)',
          },

          # Maximum allowed views
          'maxviews' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Maximum allowed views (integer as string)',
          },

          # Reference to associated metadata record
          'metadata_key' => {
            'type' => 'string',
            'description' => 'Key linking to associated metadata/receipt record',
          },

          # Original size before truncation
          'original_size' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Original content size before truncation',
          },

          # Passphrase encryption indicator
          'passphrase_encryption' => {
            'type' => 'string',
            'enum' => %w[1 2],
            'description' => 'Passphrase encryption algorithm (1=bcrypt, 2=argon2)',
          },

          # Access token
          'token' => {
            'type' => 'string',
            'description' => 'Access token for secret',
          },

          # Truncation flag
          'truncated' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Whether content was truncated',
          },

          # Encryption version
          'value_encryption' => {
            'type' => 'string',
            'description' => 'Encryption version (e.g., "2")',
          },

          # Verification status
          'verification' => {
            'type' => 'string',
            'description' => 'Verification status',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:secret_v1, SECRET)
    end
  end
end

__END__

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

### V1 Schema Coverage

**Schema has 12 fields. Dump has 18 fields.**

**In schema (12):** `key`, `value`, `value_checksum`, `custid`, `state`, `passphrase`, `secret_ttl`, `created`, `updated`, `recipient`, `share_domain`

**Missing from schema (8):**
- `lifespan` - TTL in seconds
- `maxviews` - Maximum allowed views
- `metadata_key` - Reference to associated metadata record
- `original_size` - Original size before truncation
- `passphrase_encryption` - Encryption flag for passphrase
- `token` - Access token
- `truncated` - Truncation flag
- `value_encryption` - Encryption version
- `verification` - Verification status
