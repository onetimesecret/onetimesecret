// src/tests/contracts/secret-safe-dump-fields.ts
//
// Canonical field list from Secret.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/secret/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// The contract tests will fail if the Zod schema diverges from this list,
// preventing the class of bug where Zod silently strips fields.

export const SECRET_SAFE_DUMP_FIELDS = [
  'identifier',
  'key',
  'shortid',
  'state',
  'secret_ttl',
  'lifespan',
  'has_passphrase',
  'verification',
  'created',
  'updated',
  'is_previewed',
  'is_revealed',
  'is_viewed',
  'is_received',
] as const;

export type SecretSafeDumpField = (typeof SECRET_SAFE_DUMP_FIELDS)[number];
