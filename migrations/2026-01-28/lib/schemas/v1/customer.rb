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
            'enum' => ['true', 'false', '0', '1', ''],
            'description' => 'Email verification status',
          },

          # Plan identifier
          'planid' => {
            'type' => 'string',
            'description' => 'Subscription plan identifier',
          },

          # Stripe customer ID (empty string or cus_*)
          'stripe_customer_id' => {
            'type' => 'string',
            'pattern' => '^(cus_.*)?$',
            'description' => 'Stripe customer identifier',
          },

          # Stripe subscription ID (empty string or sub_*)
          'stripe_subscription_id' => {
            'type' => 'string',
            'pattern' => '^(sub_.*)?$',
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

          # Last login timestamp (empty string or epoch float)
          'last_login' => {
            'type' => 'string',
            'pattern' => '^(\\d+(\\.\\d+)?)?$',
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
            'enum' => ['true', 'false', '0', '1', ''],
            'description' => 'Account active status',
          },

          # Contributor flag
          'contributor' => {
            'type' => 'string',
            'enum' => ['true', 'false', '0', '1', ''],
            'description' => 'Contributor flag',
          },

          # Counter: emails sent
          'emails_sent' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Number of emails sent (integer as string)',
          },

          # Duplicate of custid (deprecated)
          'key' => {
            'type' => 'string',
            'description' => 'Duplicate of custid (deprecated)',
          },

          # Hash algorithm indicator (1=bcrypt, 2=argon2)
          'passphrase_encryption' => {
            'type' => 'string',
            'enum' => %w[1 2],
            'description' => 'Passphrase hash algorithm (1=bcrypt, 2=argon2)',
          },

          # Counter: secrets burned
          'secrets_burned' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Number of secrets burned (integer as string)',
          },

          # Counter: secrets shared
          'secrets_shared' => {
            'type' => 'string',
            'pattern' => '^\\d+$',
            'description' => 'Number of secrets shared (integer as string)',
          },

          # Session ID (deprecated)
          'sessid' => {
            'type' => 'string',
            'description' => 'Session ID (deprecated)',
          },

          # Stripe checkout email
          'stripe_checkout_email' => {
            'type' => 'string',
            'description' => 'Email used in Stripe checkout',
          },
        },
        'additionalProperties' => true,
      }.freeze

      # Register the schema
      Schemas.register(:customer_v1, CUSTOMER)
    end
  end
end

__END__

## V1 Dump Field Analysis (2026-01-29)

**Source:** `exports/customer/customer_dump.jsonl`
**Total Records:** 400 customer objects

### V1 Customer Fields (22 fields)

| Field | Description | Coverage |
|-------|-------------|----------|
| `apitoken` | API authentication token | 41 with values |
| `contributor` | Contributor flag | 0 with values |
| `created` | Account creation timestamp (epoch) | 400 |
| `custid` | Customer ID (email address in v1) | 400 |
| `email` | Email address | 400 |
| `emails_sent` | Counter: emails sent | 400 |
| `key` | Duplicate of custid | 400 |
| `last_login` | Last login timestamp | 400 |
| `locale` | User locale preference | 400 |
| `passphrase` | Hashed password (bcrypt) | 397 |
| `passphrase_encryption` | Hash algorithm (1=bcrypt, 2=argon2) | 398 (all bcrypt) |
| `planid` | Subscription plan ID | 400 |
| `role` | User role (customer, etc.) | 400 |
| `secrets_burned` | Counter: secrets burned | 400 |
| `secrets_created` | Counter: secrets created | 400 |
| `secrets_shared` | Counter: secrets shared | 400 |
| `sessid` | Session ID (deprecated) | 400 |
| `stripe_checkout_email` | Stripe checkout email | 0 with values |
| `stripe_customer_id` | Stripe customer ID | 12 with values |
| `stripe_subscription_id` | Stripe subscription ID | 12 with values |
| `updated` | Last update timestamp | 400 |
| `verified` | Account verification status | 400 |

### V1 Schema Coverage

**Schema has 15 fields. Dump has 22 fields.**

**In schema (15):** `custid`, `email`, `created`, `updated`, `role`, `verified`, `planid`, `stripe_customer_id`, `stripe_subscription_id`, `locale`, `apitoken`, `passphrase`, `last_login`, `secrets_created`, `active`

**Missing from schema (7):**
- `contributor` - Contributor flag
- `emails_sent` - Counter: emails sent
- `key` - Duplicate of custid (deprecated)
- `passphrase_encryption` - Hash algorithm indicator
- `secrets_burned` - Counter: secrets burned
- `secrets_shared` - Counter: secrets shared
- `sessid` - Session ID (deprecated)
- `stripe_checkout_email` - Stripe checkout email
