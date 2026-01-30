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

---

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

### V1 → V2 Migration Notes

1. **custid/key:** In v1, both contain email address. In v2, `custid` becomes `objid` (UUIDv7).
2. **Stripe fields:** 12 customers have Stripe billing - these need to migrate to Organization.
3. **Passphrase:** All 398 hashes use bcrypt (`passphrase_encryption=1`), none use argon2.
4. **Deprecated fields:** `sessid`, `key` are deprecated in v2.

---

## Model Introspection Comparison (2026-01-29)

### Schema Fields (V2 migration schema) - 21 fields
```
objid, extid, custid, v1_custid, v1_identifier, migration_status, migrated_at,
email, created, updated, role, verified, planid, stripe_customer_id,
stripe_subscription_id, locale, apitoken, passphrase, last_login,
secrets_created, active
```

### Model Fields (Onetime::Customer) - 33 fields
```
objid, extid, created, updated, secrets_created, secrets_burned, secrets_shared,
emails_sent, role, joined, verified, verified_by, sessid, apitoken, contributor,
stripe_customer_id, stripe_subscription_id, passphrase, passphrase_encryption,
value, value_encryption, v1_identifier, migration_status, migrated_at, v1_custid,
custid, email, locale, planid, last_password_update, last_login, notify_on_reveal
```

### Discrepancies

**In schema but missing from model:**
- `active` - schema has it, model does not

**In model but missing from schema (12 fields):**

| Field | Type | Notes |
|-------|------|-------|
| `secrets_burned` | counter | Usage counter |
| `secrets_shared` | counter | Usage counter |
| `emails_sent` | counter | Usage counter |
| `contributor` | boolean | Contributor flag |
| `notify_on_reveal` | boolean | Notification preference |
| `joined` | field | Account creation timestamp |
| `verified_by` | field | Verification tracking |
| `sessid` | field | Session reference (deprecated) |
| `passphrase_encryption` | field | Encryption algorithm metadata |
| `value` | field | Generic value storage |
| `value_encryption` | field | Encryption metadata |
| `last_password_update` | field | Security timestamp |

**Related Collections (model has, schema doesn't mention):**
- `participations` (UnsortedSet)
- `custom_domains` (SortedSet)
- `receipts` (SortedSet)
