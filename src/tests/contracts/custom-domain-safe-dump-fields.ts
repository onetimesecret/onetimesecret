// src/tests/contracts/custom-domain-safe-dump-fields.ts
//
// Canonical field list from CustomDomain.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/custom_domain/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// The contract tests will fail if the Zod schema diverges from this list,
// preventing the class of bug where Zod silently strips fields.

export const CUSTOM_DOMAIN_SAFE_DUMP_FIELDS = [
  'extid',
  'domainid',
  'display_domain',
  'custid',
  'base_domain',
  'subdomain',
  'trd',
  'tld',
  'sld',
  'is_apex',
  'txt_validation_host',
  'txt_validation_value',
  'brand',
  'status',
  'vhost',
  'verified',
  'created',
  'updated',
  'sso_configured',
  'sso_enabled',
] as const;

export type CustomDomainSafeDumpField = (typeof CUSTOM_DOMAIN_SAFE_DUMP_FIELDS)[number];
