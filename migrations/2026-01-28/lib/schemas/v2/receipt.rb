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
