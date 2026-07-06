# Receipt provenance: the `source` field

Status: **Proposed** · Prompted by: the incoming-secret share-link leak · Related:
`docs/specs/receipt-page-structure/receipt-kind-model.md` (the broader structural
rethink this field is the first step of), `docs/specs/recipient-disclosure/`

This is the implementation spec for the one field the kind-model rethink depends
on. It stands alone: shipping just this field, stamped at creation and read by the
link-withholding gate, fixes the leak correctly. The rest of the rethink
(capability map, shared payload builder, per-kind frontend) builds on top later.

---

## 1. The problem the field solves

Incoming secrets must withhold the share link from their _creator_: on a custom
domain the creator is an invited guest, and opening the link would spend the one
view and break the site owner's workflow. The link (and its `secret_identifier`
bearer key) must not ship in the receipt payload for these secrets.

The distinguishing fact — "this secret was submitted by a guest through an
Incoming form" — is **provenance**, known authoritatively at creation. Two
existing fields were tried as proxies and both are wrong:

- **`kind`** (`conceal` | `generate`) is the concealment _mechanism_. An incoming
  secret is a `conceal`, indistinguishable by `kind` from an owner-created one.
- **`recipients` present?** over-triggers. An ordinary secret whose owner chose to
  _also_ email the link has recipients too — but the owner holds that link and
  must keep it. Gating on recipients-presence regresses email-shared secrets.

Provenance is orthogonal to both. It gets its own stored field.

---

## 2. The field

```ruby
# lib/onetime/models/receipt.rb  (beside :kind)
field :source   # submission provenance — see docs/specs/receipt-page-structure/receipt-source-field.md
```

**Value space** — a closed, explicit set of strings (matching the string-value
convention already used for `kind` and `state`):

| Value        | Meaning                                                       |
| ------------ | ------------------------------------------------------------ |
| `standard`   | Created by the owner (normal conceal/generate/API/email-share) |
| `incoming`   | Submitted by a guest through an Incoming Secrets form          |

String, not a boolean `incoming?`, so future surfaces (`api`, `cli`, `import`) can
be added without a schema change or a second flag. Two values satisfy today's
requirement.

---

## 3. Where it is set (creation)

Provenance is stamped at creation, never inferred at read time.

- **Incoming** — `apps/api/incoming/logic/create_incoming_secret.rb`, in the block
  that already sets `recipients` / `recipient_name` / `memo` (~line 201), before
  `receipt.save`:

  ```ruby
  receipt.source = 'incoming'
  ```

- **Everything else** — defaults to `standard`. Set it once at the model boundary
  so callers never have to think about it and legacy nils read as standard:

  ```ruby
  # Receipt.spawn_pair
  receipt.source ||= 'standard'
  ```

  `spawn_pair` is the single creation path for both members of the pair, so this
  one line covers standard, generated, and email-shared without touching their
  call sites.

---

## 4. The gate (read)

`source == 'incoming'` is the single predicate for withholding the link. Four read
sites replace their `!recipients.empty?` / `!details.show_recipients` checks:

| Site                                                        | Withholds                                        |
| ----------------------------------------------------------- | ------------------------------------------------ |
| `lib/onetime/models/receipt/features/safe_dump_fields.rb`   | `secret_identifier` (serializer — covers the noauth batch endpoint) |
| `apps/api/v2/logic/secrets/show_receipt.rb`                 | `share_url`, `share_path`, `secret_identifier`   |
| `apps/api/v1/logic/secrets/show_receipt.rb`                 | same (near-duplicate)                            |
| `src/apps/secret/components/receipt/SecretLink.vue`         | — (no change: already gates on `record.share_url` presence, which follows the payload) |

The serializer gate is load-bearing: `V3::Logic::Secrets::ShowMultipleReceipts`
builds its batch response with `map(&:safe_dump)` and never runs the logic-layer
gate, so `secret_identifier` must be withheld at `safe_dump` to close the
unauthenticated `POST /api/v3/guest/receipts` door.

**Predicate direction:** use `source.to_s == 'incoming'` (the narrow, positive
test), not `source != 'standard'`. The gate should name what it withholds from,
not fail closed on every unrecognized value.

**Contract** — `share_path` and `share_url` become nullable in
`src/schemas/contracts/receipt.ts`; a null there is the intended "link withheld"
signal, not a defect (rejecting it would null the whole receipt, #3424).

---

## 5. Legacy receipts (no migration)

Incoming receipts created before this field have `source = nil`, read as
`standard`, and revert to link-shown. That is acceptable and deliberate:

- Incoming usage is low volume and every receipt carries a short TTL, so the
  exposed tail self-expires within days.
- No backfill script, no `recipients` fallback in the gate. A fallback would drag
  the rejected proxy back into the code and re-introduce the email-shared
  regression it causes.

The gate fails _open_ on this small, self-expiring set rather than failing closed
by widening the predicate. Documented here so it is a decision, not an oversight.

---

## 6. Test coverage

- **Creation:** `create_incoming_secret` sets `source = 'incoming'`; `spawn_pair`
  defaults `source = 'standard'` for conceal / generate / email-shared.
- **Gate — incoming:** receipt payload from v1, v2, and the v3 batch endpoint omits
  `share_url` / `share_path` / `secret_identifier`.
- **Gate — email-shared (regression guard):** a `standard` receipt _with_
  recipients still ships `share_url` / `share_path` / `secret_identifier`. This is
  the case the recipients-proxy broke; it must be asserted explicitly.
- **Legacy:** a receipt with `source = nil` behaves as `standard` (link shown).
- **Contract:** `receiptCanonical` accepts null `share_path` / `share_url` without
  nulling the record.

---

## 7. Scope boundary

This spec covers only the field and the gate. It does **not** introduce the
`kind_profile` value object, the capability map, the shared payload builder, or the
per-kind frontend layouts — those are steps 2–5 of
`receipt-kind-model.md` §6 and build on the `source` field this spec adds. Shipping
this alone is correct and reversible.
