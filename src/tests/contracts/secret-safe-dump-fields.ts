// src/tests/contracts/secret-safe-dump-fields.ts
//
// Manually maintained mirror of Secret.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/secret/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// Declaration checks keep this mirror current. Real producer conformance is
// checked separately by v3-http-producer-contract.spec.ts using HTTP captures.

export const SECRET_SAFE_DUMP_FIELDS = [
  'identifier',
  'key',
  'shortid',
  'state',
  'secret_ttl',
  'lifespan',
  'has_passphrase',
  'verification',
  'display_type',
  'created',
  'updated',
  'is_previewed',
  'is_revealed',
  'is_viewed',
  'is_received',
] as const;

export type SecretSafeDumpField = (typeof SECRET_SAFE_DUMP_FIELDS)[number];
