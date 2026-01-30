# migrations/2026-01-28/lib/schemas/v2/customdomain.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 customdomain data (output after transformation).
      #
      # V2 customdomains use UUIDv7 objid as identifier, have extid for URLs,
      # reference owner (customer) and organization via objids,
      # and include migration tracking fields.
      #
      CUSTOMDOMAIN = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'CustomDomain V2',
        'description' => 'V2 customdomain record after migration transformation',
        'type' => 'object',
        'required' => %w[objid display_domain owner_id migration_status migrated_at],
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
            'pattern' => '^cd[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

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

          # Owner customer objid (UUIDv7)
          'owner_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Organization objid (UUIDv7)
          'org_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Organization objid (UUIDv7)',
          },

          # Original V1 custid (email) preserved for reference
          'v1_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer identifier (email)',
          },

          # Original V1 key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^customdomain:.+:object$',
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

          # TXT validation fields
          'txt_validation_value' => {
            'type' => 'string',
            'description' => 'TXT record validation value',
          },
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
      Schemas.register(:customdomain_v2, CUSTOMDOMAIN)
    end
  end
end
