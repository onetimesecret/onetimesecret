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
      SECRET = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Secret V2',
        'description' => 'V2 secret record after migration transformation',
        'type' => 'object',
        'required' => %w[objid value migration_status migrated_at],
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
            'pattern' => '^se[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Owner customer objid (optional for anonymous secrets)
          'owner_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid (optional for anonymous secrets)
          'org_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # Encrypted value (CRITICAL - preserved exactly from V1)
          'value' => {
            'type' => 'string',
            'description' => 'Encrypted secret content (preserved exactly)',
          },

          # Checksum of the value
          'value_checksum' => {
            'type' => 'string',
            'description' => 'Checksum of the encrypted value',
          },

          # Secret state
          'state' => {
            'type' => 'string',
            'enum' => %w[new viewed received burned],
            'description' => 'Secret state',
          },

          # Time to live in seconds
          'secret_ttl' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Secret TTL in seconds (integer as string)',
          },

          # Whether secret has a passphrase (stored as boolean string, empty allowed)
          'passphrase' => {
            'type' => 'string',
            'enum' => ['0', '1', 'true', 'false', ''],
            'description' => 'Whether secret is passphrase protected',
          },

          # Timestamps
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

          # Migration tracking
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^secret:.+:object$',
            'description' => 'Original V1 Redis key',
          },
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
