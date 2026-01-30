# migrations/2026-01-28/lib/schemas/v2/organization.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 organization data (newly generated records).
      #
      # Organizations are NEW in V2 - one is created per Customer.
      # All values are strings since Redis hashes only store strings.
      #
      ORGANIZATION = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Organization V2',
        'description' => 'V2 organization record generated during migration',
        'type' => 'object',
        'required' => %w[objid owner_id contact_email is_default migration_status migrated_at],
        'properties' => {
          # Primary identifier (UUIDv7)
          'objid' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Object identifier (UUIDv7)',
          },

          # External identifier for URLs
          'extid' => {
            'type' => 'string',
            'pattern' => '^on[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Display name for UI
          'display_name' => {
            'type' => 'string',
            'description' => 'Human-readable display name',
          },

          # Optional description
          'description' => {
            'type' => ['string', 'null'],
            'description' => 'Organization description',
          },

          # Owner customer objid
          'owner_id' => {
            'type' => 'string',
            'pattern' => '^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            'description' => 'Owner customer objid (UUIDv7)',
          },

          # Contact email (from customer)
          'contact_email' => {
            'type' => 'string',
            'description' => 'Primary contact email',
          },

          # Billing email
          'billing_email' => {
            'type' => 'string',
            'description' => 'Billing contact email',
          },

          # Default organization flag
          'is_default' => {
            'type' => 'string',
            'enum' => %w[true false],
            'description' => 'Whether this is the default organization',
          },

          # Plan identifier
          'planid' => {
            'type' => 'string',
            'description' => 'Subscription plan identifier',
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

          # Stripe identifiers (inherited from customer, empty string allowed for unset)
          'stripe_customer_id' => {
            'type' => 'string',
            'pattern' => '^(cus_.*|)$',
            'description' => 'Stripe customer identifier',
          },
          'stripe_subscription_id' => {
            'type' => 'string',
            'pattern' => '^(sub_.*|)$',
            'description' => 'Stripe subscription identifier',
          },
          'stripe_checkout_email' => {
            'type' => 'string',
            'description' => 'Stripe checkout email',
          },

          # Migration tracking
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^customer:.+:object$',
            'description' => 'Original V1 customer Redis key (source of this org)',
          },
          'v1_source_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer identifier (email)',
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
      Schemas.register(:organization_v2, ORGANIZATION)
    end
  end
end


__END__

## Source Files
- Ruby Schema: migrations/2026-01-28/lib/schemas/v2/organization.rb
- Spec.md: migrations/2026-01-26/02-organization/spec.md
- Zod Schema: src/types/organization.ts

---
Organization
┌─────────────────┬──────────────────────────────────────────────────┬──────────────┬─────────────────────────────────────────────────────────────────────┐
│    Category     │                   Ruby Schema                    │   Spec.md    │                             Zod (truth)                             │
├─────────────────┼──────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────────────────────────────────────┤
│ Field renames   │ objid→id, created→created_at, updated→updated_at │ Same issue   │ Uses id, created_at, updated_at                                     │
├─────────────────┼──────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────────────────────────────────────┤
│ Owner field     │ Has owner_id (ObjId)                             │ Has owner_id │ Expects owner_extid (ExtId)                                         │
├─────────────────┼──────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────────────────────────────────────┤
│ Type mismatch   │ is_default is string                             │ —            │ Expects boolean                                                     │
├─────────────────┼──────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────────────────────────────────────┤
│ Computed fields │ Missing all                                      │ Missing all  │ member_count, current_user_role, entitlements, limits, domain_count │
├─────────────────┼──────────────────────────────────────────────────┼──────────────┼─────────────────────────────────────────────────────────────────────┤
│ contact_email   │ Required                                         │ Required     │ Nullable (nullish)                                                  │
└─────────────────┴──────────────────────────────────────────────────┴──────────────┴─────────────────────────────────────────────────────────────────────┘
Updates needed:
- Ruby: Rename 3 fields, add owner_extid, fix is_default type, add computed fields
- Spec: Rename owner_id→owner_extid, created→created_at; add updated_at, computed fields
