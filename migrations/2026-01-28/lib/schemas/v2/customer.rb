# migrations/2026-01-28/lib/schemas/v2/customer.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V2
      # JSON Schema for V2 customer data (output after transformation).
      #
      # V2 customers use UUIDv7 objid as custid, have extid for URLs,
      # and include migration tracking fields.
      #
      CUSTOMER = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Customer V2',
        'description' => 'V2 customer record after migration transformation',
        'type' => 'object',
        'required' => %w[objid custid migration_status migrated_at],
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
            'pattern' => '^ur[0-9a-zA-Z]+$',
            'description' => 'External identifier for URL paths',
          },

          # Customer ID (now equals objid in V2)
          'custid' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Customer identifier (objid in V2)',
          },

          # Original V1 custid (email) preserved for lookup
          'v1_custid' => {
            'type' => 'string',
            'description' => 'Original V1 customer identifier (email)',
          },

          # Original V1 key for audit trail
          'v1_identifier' => {
            'type' => 'string',
            'pattern' => '^customer:.+:object$',
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

          # Email (may differ from v1_custid if normalized)
          'email' => {
            'type' => 'string',
            'description' => 'Email address',
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

          # Role
          'role' => {
            'type' => 'string',
            'enum' => %w[customer colonel recipient anonymous],
            'description' => 'User role',
          },

          # Verification status
          'verified' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Email verification status',
          },

          # Plan identifier
          'planid' => {
            'type' => 'string',
            'description' => 'Subscription plan identifier',
          },

          # Stripe identifiers (empty string allowed for unset)
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

          # Locale
          'locale' => {
            'type' => 'string',
            'description' => 'User locale preference',
          },

          # API token
          'apitoken' => {
            'type' => 'string',
            'description' => 'API authentication token',
          },

          # Passphrase (hashed)
          'passphrase' => {
            'type' => 'string',
            'description' => 'Hashed authentication passphrase',
          },

          # Last login timestamp (empty string allowed for never logged in)
          'last_login' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?|)$',
            'description' => 'Last login timestamp (epoch float as string)',
          },

          # Secret count
          'secrets_created' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Total secrets created (integer as string)',
          },

          # Active status
          'active' => {
            'type' => 'string',
            'enum' => %w[true false 0 1],
            'description' => 'Account active status',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:customer_v2, CUSTOMER)
    end
  end
end


__END__

## Source Files
- Ruby Schema: migrations/2026-01-28/lib/schemas/v2/customer.rb
- Spec.md: migrations/2026-01-26/01-customer/spec.md
- Zod Schema: src/schemas/models/customer.ts

---
Customer
┌────────────────┬────────────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────┬───────────────────────┐
│    Category    │                                Ruby Schema                                 │                    Spec.md                    │      Zod (truth)      │
├────────────────┼────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
│ Base fields    │ Missing: identifier                                                        │ Missing: identifier, created, updated, active │ Has all               │
├────────────────┼────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
│ Role enum      │ Has anonymous                                                              │ —                                             │ Has user_deleted_self │
├────────────────┼────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
│ Missing fields │ contributor, secrets_burned, secrets_shared, emails_sent, notify_on_reveal │ —                                             │ Has all               │
├────────────────┼────────────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────┼───────────────────────┤
│ Backend-only   │ stripe_*, apitoken, passphrase (acceptable)                                │ Same                                          │ Not exposed           │
└────────────────┴────────────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────┴───────────────────────┘
Updates needed:
- Ruby: Add 6 fields, fix role enum
- Spec: Add identifier, created, updated, active to Direct Copy
