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

          # Whether secret has a passphrase (stored as boolean string, empty allowed)
          'passphrase' => {
            'type' => 'string',
            'enum' => ['0', '1', 'true', 'false', ''],
            'description' => 'Whether secret is passphrase protected',
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
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:secret_v1, SECRET)
    end
  end
end
