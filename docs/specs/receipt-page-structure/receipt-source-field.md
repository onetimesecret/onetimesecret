# Receipt provenance: the `source` field

Status: **Implemented** · Prompted by: the incoming-secret share-link leak · Related:
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
convention already used for `kind` and `state`), declared beside the field the
way `Customer::PROVISIONING_ORIGINS` declares its provenance set:

```ruby
SOURCES = %w[standard incoming].freeze
```

| Value        | Meaning                                                       |
| ------------ | ------------------------------------------------------------ |
| `standard`   | Created by the owner (normal conceal/generate/API/email-share) |
| `incoming`   | Submitted by a guest through an Incoming Secrets form          |

String, not a boolean `incoming?`, so future surfaces (`api`, `cli`, `import`) can
be added without a schema change or a second flag. Two values satisfy today's
requirement.

**Read behaviour lives in a capability map, not scattered comparisons.** Rather
than repeat `source == 'incoming'` at every gate, source-dependent behaviour is a
single frozen map keyed by `source` (mirroring
`CustomDomain::SignupConfig::STRATEGY_METADATA`), read through one model predicate:

```ruby
SOURCE_CAPABILITIES = {
  'standard' => { shows_share_link: true }.freeze,
  'incoming' => { shows_share_link: false }.freeze,
}.freeze
WITHHELD_CAPABILITIES = { shows_share_link: false }.freeze  # fail closed

def shows_share_link?
  return true if source.to_s.empty?   # legacy pre-field receipt → standard
  SOURCE_CAPABILITIES.fetch(source.to_s, WITHHELD_CAPABILITIES)[:shows_share_link]
end
```

This collapses the four gates into one authority and makes the fail direction an
explicit one-line policy: unrecognized non-empty values **fail closed** (link
withheld); only the empty/`nil` legacy case is shown (see §5). Familia round-trips
an unset declared field through the stored string `"null"` back to `nil` on read
(`deserialize_value`), so `source.to_s.empty?` covers absent, `nil`, `""`, and
stored-`"null"` alike.

---

## 3. Where it is set (creation)

Provenance is stamped at creation, never inferred at read time.

- **Incoming** — `apps/api/incoming/logic/create_incoming_secret.rb`, in the block
  that already sets `recipients` / `recipient_name` / `memo` (~line 201), before
  `receipt.save`:

  ```ruby
  receipt.source = 'incoming'
  ```

- **Everything else** — defaults to `standard`, set in `Receipt#init` beside the
  sibling discriminator's default so every `.new` path is covered (not just
  `spawn_pair`) and callers never think about it:

  ```ruby
  def init
    self.state  ||= 'new'
    self.source ||= 'standard'
  end
  ```

  `init` runs on construction for standard, generated, and email-shared receipts
  alike. For incoming, `spawn_pair` constructs the receipt (so `init` defaults it
  to `standard`) and `create_incoming_secret` then overrides to `'incoming'`
  before its `save` — a plain assignment wins over the `||=` default.

---

## 4. The gate (read)

`Receipt#shows_share_link?` (the capability-map predicate from §2) is the single
authority for withholding the link. Four read sites call it instead of the
`!recipients.empty?` / `!details.show_recipients` checks they used to carry:

| Site                                                        | Withholds when `!shows_share_link?`              |
| ----------------------------------------------------------- | ------------------------------------------------ |
| `lib/onetime/models/receipt/features/safe_dump_fields.rb`   | `secret_identifier` (serializer — covers the noauth batch endpoint) |
| `apps/api/v2/logic/secrets/show_receipt.rb`                 | `share_url`, `share_path`, `secret_identifier`   |
| `apps/api/v1/logic/secrets/show_receipt.rb`                 | `share_url`, `share_path`, `secret_key` (near-duplicate) |
| `src/apps/secret/components/receipt/SecretLink.vue`         | — (no gating change: already hidden for recipient-bearing receipts; only made `share_url` null-safe for the nullable contract) |

The serializer gate is load-bearing: `V3::Logic::Secrets::ShowMultipleReceipts`
builds its batch response with `map(&:safe_dump)` and never runs the logic-layer
gate, so `secret_identifier` must be withheld at `safe_dump` to close the
unauthenticated `POST /api/v3/guest/receipts` door. `safe_dump` also now emits
`:source` (alongside `:kind`) so the frontend can see provenance directly.

**Predicate direction:** the gate **fails closed** — an unrecognized non-empty
`source` (a typo, or an unshipped future value someone forgot to add to
`SOURCE_CAPABILITIES`) withholds the link. Only the empty/`nil` legacy case is
shown (§5), because that population is the entire pre-field table and is
overwhelmingly `standard` — failing closed there would strip the link from every
legacy receipt. This is one line in the predicate (`fetch(..., WITHHELD)` + the
empty carve-out), not a `==`-vs-`!=` choice scattered across four files.

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

Model, predicate, and the load-bearing serializer gate:
`try/unit/models/receipt_safe_dump_try.rb`. Contract: the frontend receipt schema
suite (`src/tests/contracts/`, `src/tests/schemas/shapes/`). Logic-layer gate:
`apps/api/v1/spec/logic/secrets/show_receipt_spec.rb` (its receipt double stubs
`shows_share_link?`).

- **Creation / default:** `init` defaults `source = 'standard'` (asserted on
  `Receipt.new`); `create_incoming_secret` overrides to `'incoming'`.
- **Predicate matrix:** `shows_share_link?` is true for `standard`, false for
  `incoming`, true for empty/`nil` (legacy), false for an unrecognized non-empty
  value (fail closed).
- **Gate — incoming:** `safe_dump` omits `secret_identifier` (this closes the v3
  noauth batch door directly, since that endpoint is `map(&:safe_dump)`); v1/v2
  logic additionally null `share_url` / `share_path`.
- **Gate — email-shared (regression guard):** a `standard` receipt _with_
  recipients still ships `secret_identifier` (and the URLs). This is the case the
  recipients-proxy broke; asserted explicitly.
- **Legacy:** a receipt with `source = nil` behaves as `standard` (link shown).
- **Contract:** `receiptCanonical` accepts null `share_path` / `share_url` without
  nulling the record; adds a nullable `source` enum.

---

## 7. Scope boundary

This spec covers only the field and the gate. It does **not** introduce the
`kind_profile` value object, the capability map, the shared payload builder, or the
per-kind frontend layouts — those are steps 2–5 of
`receipt-kind-model.md` §6 and build on the `source` field this spec adds. Shipping
this alone is correct and reversible.
