# try/unit/api/v3/secrets/receipt_shape_try.rb
#
# frozen_string_literal: true

# Tests for V3::Logic::ReceiptShape, the V3-only receipt wire-shape normalizer
# (2026-07-29 API audit, items 5 and 7).
#
# V1/V2 share lib/onetime/models/receipt/features/safe_dump_fields.rb and are
# frozen on its output, so V3 corrects the shape at its own serialization
# boundary:
#
#   custid      deprecated; always null on post-migration records. Dropped.
#   recipients  a ', '-joined String from safe_dump. Emitted as null-or-Array.
#
# The module is dependency-free by design (plain Hash in, plain Hash out), so
# this file requires it directly instead of booting the app.

require_relative '../../../../../apps/api/v3/logic/receipt_shape'

@shape = V3::Logic::ReceiptShape

## Blank recipients string becomes nil, not an empty array
@shape.normalize_recipients('')
#=> nil

## Nil recipients stays nil
@shape.normalize_recipients(nil)
#=> nil

## A single obscured address becomes a one-element array
@shape.normalize_recipients('t***@e***.com')
#=> ['t***@e***.com']

## The ', '-joined form written by Receipt#deliver_by_email splits on the comma
@shape.normalize_recipients('a***@e***.com, b***@f***.com')
#=> ['a***@e***.com', 'b***@f***.com']

## An already-array value is passed through, blanks dropped
@shape.normalize_recipients(['x@y.com', '', nil])
#=> ['x@y.com']

## An empty array collapses to nil so consumers branch on one thing
@shape.normalize_recipients([])
#=> nil

## custid is deleted from a receipt hash; owner_id survives
@receipt = { custid: 'anon', owner_id: 'ur_abc123', recipients: '' }
@shape.normalize_receipt!(@receipt)
#=> {owner_id: 'ur_abc123', recipients: nil}

## A record with neither field is left untouched (secret safe_dumps share the
## :record slot on ShowSecret / RevealSecret / ListSecretStatus)
@secret = { identifier: 'sec123', state: 'new' }
@shape.normalize_receipt!(@secret)
#=> {identifier: 'sec123', state: 'new'}

## Conceal/generate envelope: record.receipt is normalized, record.secret is not
@conceal = {
  record: {
    receipt: { custid: 'anon', owner_id: 'ur_1', recipients: 'a***@b***.com' },
    secret: { identifier: 'sec1', state: 'new' },
  },
  details: { kind: 'conceal', recipient: ['z@y.com'] },
}
@shape.normalize!(@conceal)
#=> {record: {receipt: {owner_id: 'ur_1', recipients: ['a***@b***.com']}, secret: {identifier: 'sec1', state: 'new'}}, details: {kind: 'conceal', recipient: ['z@y.com']}}

## details.recipient is a different field (the request echo) and is preserved
@conceal.dig(:details, :recipient)
#=> ['z@y.com']

## Show/burn/update envelope: record IS the receipt
@show = { record: { custid: 'c', owner_id: 'ur_2', recipients: 'p***@q***.com', memo: 'm' } }
@shape.normalize!(@show)
#=> {record: {owner_id: 'ur_2', recipients: ['p***@q***.com'], memo: 'm'}}

## List envelope: string-keyed (ListReceipts) records array is normalized
@list = {
  'records' => [
    { custid: nil, recipients: '' },
    { custid: 'x', recipients: 'p***@q***.com, r***@s***.com' },
  ],
  'count' => 2,
}
@shape.normalize!(@list)
#=> {'records' => [{recipients: nil}, {recipients: ['p***@q***.com', 'r***@s***.com']}], 'count' => 2}

## Symbol-keyed records array (ShowMultipleReceipts) is normalized too
@batch = { records: [{ custid: 'y', recipients: 'solo@example.com' }], count: 1 }
@shape.normalize!(@batch)
#=> {records: [{recipients: ['solo@example.com']}], count: 1}

## A nil envelope passes through (RevealSecret/ShowSecret return nil on miss)
@shape.normalize!(nil)
#=> nil

## Normalization is idempotent
@twice = { record: { custid: 'c', recipients: 'a@b.com' } }
@shape.normalize!(@shape.normalize!(@twice))
#=> {record: {recipients: ['a@b.com']}}
