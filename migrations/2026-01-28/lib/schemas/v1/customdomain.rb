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
