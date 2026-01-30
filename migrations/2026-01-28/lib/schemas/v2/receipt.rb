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
            'pattern' => '^\\d+(\\.\\d+)?$',
            'description' => 'Timestamp when secret was received',
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
