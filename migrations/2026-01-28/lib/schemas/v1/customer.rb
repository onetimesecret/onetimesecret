# migrations/2026-01-28/lib/schemas/v1/customer.rb
#
# frozen_string_literal: true

require_relative '../base'

module Migration
  module Schemas
    module V1
      # JSON Schema for V1 customer data (input from Redis HGETALL).
      #
      # V1 customers use email as custid and store fields as Redis hash.
      # All values are strings since Redis hashes only store strings.
      #
      CUSTOMER = {
        '$schema' => 'http://json-schema.org/draft-07/schema#',
        'title' => 'Customer V1',
        'description' => 'V1 customer record from Redis hash (pre-migration)',
        'type' => 'object',
        'required' => %w[custid],
        'properties' => {
          # Primary identifier (email in V1)
          'custid' => {
            'type' => 'string',
            'minLength' => 1,
            'description' => 'Customer identifier (email address in V1)',
          },

          # Optional email (may be absent if custid is email)
          'email' => {
            'type' => 'string',
            'description' => 'Email address',
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

          # Role (customer, colonel, recipient, anonymous)
          'role' => {
            'type' => 'string',
            'enum' => %w[customer colonel recipient anonymous],
            'description' => 'User role',
          },

          # Verification status (stored as string boolean or 0/1)
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

          # Stripe customer ID
          'stripe_customer_id' => {
            'type' => 'string',
            'pattern' => '^cus_',
            'description' => 'Stripe customer identifier',
          },

          # Stripe subscription ID
          'stripe_subscription_id' => {
            'type' => 'string',
            'pattern' => '^sub_',
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

          # Last login timestamp
          'last_login' => {
            'type' => 'string',
            'pattern' => '^\\d+(\\.\\d+)?$',
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
      Schemas.register(:customer_v1, CUSTOMER)
    end
  end
end
