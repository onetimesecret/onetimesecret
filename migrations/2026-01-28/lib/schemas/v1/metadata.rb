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

          # Secret value (encrypted, may be present in some records)
          'secret_value' => {
            'type' => 'string',
            'description' => 'Encrypted secret value (if embedded)',
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
      Schemas.register(:metadata_v1, METADATA)
    end
  end
end
