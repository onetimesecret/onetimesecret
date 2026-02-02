# migrations/2026-01-28/lib/schemas/v1/metadata.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V1
      # JSON Schema for V1 metadata data (input from Redis HGETALL).
      #
      # V1 metadata tracks secret lifecycle (receipt records).
      # The "key" field is the secret key this receipt tracks.
      # All values are strings since Redis hashes only store strings.
      #
      METADATA = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Metadata V1',
        'description' => 'V1 metadata/receipt record from Redis hash (pre-migration)',
        'type' => 'object',
        'required' => %w[key],
        'properties' => {
          # The secret key this receipt tracks (primary identifier)
          'key' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Secret key this receipt tracks',
          },

          # Customer identifier (email in V1)
          'custid' => {
            'type' => 'string',
            'description' => 'Customer identifier (email address in V1)',
          },

          # Lifecycle state
          'state' => {
            'type' => 'string',
            'enum' => %w[new viewed received burned],
            'description' => 'Receipt/secret lifecycle state',
          },

          # Short key for display (first 8 chars)
          'secret_shortkey' => {
            'type' => 'string',
            'description' => 'Short version of secret key for display',
          },

          # Recipients (comma-separated or array serialized)
          'recipients' => {
            'type' => 'string',
            'description' => 'Comma-separated recipient emails',
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

          # Temporary passphrase (if set during secret creation)
          'passphrase_temp' => {
            'type' => 'string',
            'description' => 'Temporary passphrase indicator',
          },

          # Custom domain used when sharing
          'share_domain' => {
            'type' => 'string',
            'description' => 'Custom domain FQDN used for sharing',
          },

          # TTL in seconds for the secret
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

          # TTL duration set when created (V1 field name)
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
      Schemas.register(:metadata_v1, METADATA)
    end
  end
end

__END__

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

### V1 Schema Coverage

**Schema has 13 fields. Dump has 19 fields.**

**In schema (13):** `key`, `custid`, `state`, `secret_shortkey`, `recipients`, `created`, `updated`, `passphrase_temp`, `share_domain`, `ttl`, `view_count`, `received`

**Missing from schema (10):**
- `burned` - Timestamp when the secret was burned
- `lifespan` - TTL duration that was set when created
- `memo` - Optional memo/subject for incoming secrets
- `passphrase` - Passphrase indicator/value (if set)
- `secret_key` - Full secret key reference
- `secret_ttl` - Time-to-live in seconds for the secret
- `shared` - Timestamp when secret was shared
- `token` - Receipt token/identifier
- `truncate` - Truncation indicator
- `viewed` - Timestamp when secret was previewed (by owner)
