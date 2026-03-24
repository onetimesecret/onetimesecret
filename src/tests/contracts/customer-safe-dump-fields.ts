// src/tests/contracts/customer-safe-dump-fields.ts
//
// Canonical field list from Customer.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/customer/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// The contract tests will fail if the Zod schema diverges from this list,
// preventing the class of bug where Zod silently strips fields.

export const CUSTOMER_SAFE_DUMP_FIELDS = [
  'objid',
  'extid',
  'email',
  'role',
  'verified',
  'last_login',
  'locale',
  'updated',
  'created',
  'secrets_created',
  'secrets_burned',
  'secrets_shared',
  'emails_sent',
  'active',
  'notify_on_reveal',
] as const;

export type CustomerSafeDumpField = (typeof CUSTOMER_SAFE_DUMP_FIELDS)[number];
