# AZ6 — Receipt safe_dump exposes creator custid/owner_id via anonymous endpoints

- **Severity:** Low — **CONFIRMED**
- **Status:** Proposed fix
- **Affects default config?** Yes (anonymous receipt show/burn/batch is default behavior)
- **Related:** finding 02 F6; AZ2 (same internal-ID-leak class for Organization)
- **Primary files:** `lib/onetime/models/receipt/features/safe_dump_fields.rb:54-57`,
  `apps/api/v3/logic/secrets.rb:216-255` (`ShowMultipleReceipts`),
  v2 receipt show/burn paths that also serialize via `safe_dump`

## Problem (recap)

Receipt `safe_dump` emits the creator's internal customer identifiers:

```ruby
# lib/onetime/models/receipt/features/safe_dump_fields.rb:54-57
base.safe_dump_field :identifier, ->(obj) { obj.identifier }
base.safe_dump_field :key, ->(obj) { obj.identifier }
base.safe_dump_field :custid       # :56 — creator's internal customer id
base.safe_dump_field :owner_id     # :57 — creator's internal customer id
```

Receipts use a **possession-based** access model (assessment §3, F12): holding the receipt identifier is the
credential, and show/burn are reachable **anonymously**. `ShowMultipleReceipts` returns `safe_dump` for up to
25 receipts by id with no authentication:

```ruby
# apps/api/v3/logic/secrets.rb:246-249
def process
  receipt_objects = Onetime::Receipt.load_multi(identifiers).compact
  @records        = receipt_objects.map(&:safe_dump)   # includes custid + owner_id
  success_data
end
```

So any party holding a receipt identifier learns the creator's internal customer custid/owner_id. Severity is
Low — the identifier is an unguessable 256-bit HMAC-signed value typically held only by the creator — but the
internal customer id has no reason to be in an anonymously-reachable dump, and it enables correlation of
multiple receipts to one customer.

## Root cause

Same shape as AZ2: a single `safe_dump` field map is reused across all audiences, including an
unauthenticated possession-based path. Internal owner identifiers were included for the *authenticated owner's*
own listing views but are emitted unconditionally, including to anonymous callers. `safe_dump` is an allowlist
of fields, but the allowlist itself includes the sensitive ids.

## Prescribed resolution

Drop the internal creator identifiers (`custid`, `owner_id`) from the Receipt `safe_dump` allowlist. Display
flags that legitimately need "is this mine?" already come from `Receipt#owner?(cust)`
(assessment §3, `receipt.rb:148-150`) computed in the logic layer, not from emitting the raw custid.

### Implementation steps

1. Remove the two internal-id fields from the Receipt dump:

   ```ruby
   # lib/onetime/models/receipt/features/safe_dump_fields.rb — delete:
   base.safe_dump_field :custid      # :56
   base.safe_dump_field :owner_id    # :57
   ```

   The remaining fields (`identifier`/`key`, `state`, `secret_shortid`, `secret_identifier`, counters, etc.)
   are what the possession-based UI actually needs.

2. If an authenticated owner view genuinely needs to confirm ownership, expose a **derived boolean** computed
   in the logic class rather than the raw id — and only on authenticated paths:

   ```ruby
   # In an authenticated receipt logic class (e.g. list_receipts / update_receipt response builder)
   dump = receipt.safe_dump
   dump[:is_owner] = receipt.owner?(cust)   # boolean, no internal id leaked
   ```

   The anonymous `ShowMultipleReceipts`/show/burn paths emit the id-free dump and never compute ownership
   for an anonymous caller.

3. Verify the v2 show/burn serialization (`apps/api/v2/logic/secrets/*`) and v1 paths all funnel through the
   same `safe_dump`, so removing the fields covers every API version at once (no per-version edit needed).

### Alternatives considered

- **Strip custid/owner_id only in the anonymous serialization path:** more code and more chances to miss a
  path. Since no audience needs the raw internal id in the dump, removing it from the allowlist is simpler and
  strictly safer.
- **Replace custid with the creator's `extid`:** still leaks creator identity to anonymous holders. For a
  possession-based receipt there is no need to disclose *who* created it; drop it entirely.

## Test / verification

Add to `apps/api/v3/spec/logic/secrets/` (and a v2 receipt spec):
1. **Anonymous batch:** `ShowMultipleReceipts` for a known receipt id → response contains `identifier`/
   `state` but **no** `custid` or `owner_id`.
2. **Anonymous show/burn:** single receipt dump → no `custid`/`owner_id`.
3. **Authenticated owner view (if step 2 added):** `is_owner` boolean is present and correct, still no raw
   internal id.
4. **JSON-key snapshot:** diff the receipt response keys against frontend/SDK consumers to catch readers of
   the removed fields.

## Effort & risk

- **Effort:** Low — two deleted field registrations, optional `is_owner` helper, and specs.
- **Back-compat:** removing `custid`/`owner_id` changes the receipt JSON shape; grep consumers first. They are
  internal ids, so legitimate clients should not depend on them.
- **Risk:** Low. Possession-based access is unchanged; only the emitted creator id is removed.
