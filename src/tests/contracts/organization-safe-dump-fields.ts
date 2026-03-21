// src/tests/contracts/organization-safe-dump-fields.ts
//
// Canonical field list from Organization.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/organization/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// The contract tests will fail if the Zod schema diverges from this list,
// preventing the class of bug where Zod silently strips fields.

export const ORGANIZATION_SAFE_DUMP_FIELDS = [
  'identifier',
  'objid',
  'extid',
  'display_name',
  'description',
  'owner_id',
  'contact_email',
  'billing_email',
  'is_default',
  'planid',
  'member_count',
  'domain_count',
  'updated',
  'created',
  'entitlements',
  'limits',
] as const;

export type OrganizationSafeDumpField = (typeof ORGANIZATION_SAFE_DUMP_FIELDS)[number];
