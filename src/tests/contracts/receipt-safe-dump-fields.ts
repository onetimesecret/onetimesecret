// src/tests/contracts/receipt-safe-dump-fields.ts
//
// Canonical field list from Receipt.safe_dump_fields (Ruby backend).
// Source: lib/onetime/models/receipt/features/safe_dump_fields.rb
//
// Update this list when safe_dump_fields.rb changes.
// The contract tests will fail if the Zod schema diverges from this list,
// preventing the class of bug where Zod silently strips fields.

export const RECEIPT_SAFE_DUMP_FIELDS = [
  'identifier',
  'key',
  'custid',
  'owner_id',
  'state',
  'secret_shortid',
  'secret_identifier',
  'secret_ttl',
  'metadata_ttl',
  'receipt_ttl',
  'lifespan',
  'share_domain',
  'created',
  'updated',
  'shared',
  'recipients',
  'memo',
  'shortid',
  'show_recipients',
  'previewed',
  'revealed',
  'is_previewed',
  'viewed',
  'received',
  'burned',
  'is_viewed',
  'is_received',
  'is_revealed',
  'is_burned',
  'is_expired',
  'is_orphaned',
  'is_destroyed',
  'has_passphrase',
  'kind',
] as const;

export type ReceiptSafeDumpField = (typeof RECEIPT_SAFE_DUMP_FIELDS)[number];
