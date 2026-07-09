# "secret shows 'no longer available'": root cause and failure surface

Companion to the systemic design in #3496 / #3514
(`docs/specs/schemata/schema-source-of-truth.md`). That spec proposes the cure; this one
establishes what actually fails, and why the per-field fixes #3268, #3434, #3477,
and #3494 did not close the issue. It describes current `develop`.

## The bug, and why it is subtle

A recipient opens a link; `GET /api/v3/guest/secret/:id` returns HTTP 200; the
frontend `gracefulParse(responseSchemas.secret, …)` rejects the payload; `record`
stays null; the recipient sees the terminal "no longer available" view; the
sender dashboard shows "Previewed", never "Viewed".

Four properties of the code constrain where the failure can be:

1. The reveal record is `secret.safe_dump` (`ShowSecret#success_data`; V3 inherits
   it unchanged — there is no separate V3 serializer).
2. `safe_dump` coerces the four originally-blamed fields unconditionally:
   `lifespan`/`secret_ttl` via `to_i`, `created`/`updated` via `to_f` (and
   `nil.to_f == 0.0`). None can be string- or null-typed on the wire.
3. The 200 is gated by `Secret#viewable?`, true only for `state ∈ {new,
   previewed}`. Any other state raises `MissingSecret` (→ 404) before a body is
   built, so a parsed secret payload always carries an in-enum `state`.
4. The contract is strict by intent: #3477 reverted a `z.number().nullable()`
   widening back to `z.number()`. The strategy is enforce-at-read,
   clean-at-source — not coerce-on-read.

These force two conclusions. The recipient `ShowSecret` payload validates for any
healthy, current secret, so #3424 is not that path on healthy data. And it was
never one field: it is a *class* of strict-schema mismatches whose members live
on other paths. Three fixes missed because the failing field was discarded in
production — `gracefulParse` logged a generic string and put `issues[].path` only
in non-searchable telemetry — so each fix targeted an inferred field.

## The failure surface

Every member of the class is a record field the contract types strictly while the
backend can emit a non-conforming value on a path that bypasses the four
`safe_dump` numeric casts. `src/tests/contracts/issue-3424-failing-field-forensics.spec.ts`
runs the real V3 schemas against wire-faithful payloads and is the authoritative
enumeration. The classes:

| Path | Field(s) | Non-conforming value | Status |
|---|---|---|---|
| `ListReceipts`, `ShowReceipt` | `state`, `secret_state` | legacy `viewed`/`received` (enum excludes them) | open (see below) |
| `ShowReceipt#_receipt_attributes` | `expiration_in_seconds` | raw `secret_ttl`, string when poisoned | coerced (`to_i`) |
| `ShowReceipt#_receipt_attributes` | `expiration` | `nil` for a consumed/expired secret | contract nullable |
| receipt `safe_dump` | `previewed`/`revealed`/`burned`/`shared` | raw timestamp, string or `""` when poisoned | coerced (`to_i`, Integer or nil) |
| recipient `ShowSecret` | none on healthy data | — | — |

Two structural properties make any single member fatal:

- The contract is an all-or-nothing gate: one non-conforming field nulls the
  whole record, and on the list endpoint one bad row nulls the whole dashboard.
- The recipient and sender symptoms share one terminal view. A `viewable?` 404
  (legacy/consumed) and a `gracefulParse` failure render the same "no longer
  available" screen, so the two causes are indistinguishable from the report.

## Why per-field casting could not close it

`safe_dump` coercion is correct but incomplete by construction: it covers the
fields someone enumerated, on the one serialization path that runs through it. The
receipt single-record payload is `safe_dump` *merged with* raw computed values in
`ShowReceipt#_receipt_attributes`, which no cast reaches; the receipt timestamps
had no coercion lambda; and `state` is a strict enum fed the raw stored value with
no normalization. Because Familia v2 storage is type-preserving rather than
type-enforcing, the supply of wrong-typed values is open-ended — the next
uncovered field is guaranteed. Each prior fix was also validated only against
`state: 'new'` fixtures, which cannot exhibit the legacy-state or raw-merge
members.

## Root causes

1. Storage is type-preserving, not type-enforcing (Familia v2): a wrong-typed
   value round-trips indefinitely; there is no `field :x, type: Integer`.
2. The write paths that inject wrong types are open-ended (ERB/ENV, YAML floats,
   raw params, console); #3299 closed two, but there is no single choke point.
3. The read contract is strict and all-or-nothing, and was authored to the
   idealized model rather than to what `safe_dump` plus logic merges emit across
   the real keyspace.
4. Remediation sat at the wrong layer: per-field `safe_dump` casts miss the raw
   merges, the receipt timestamps, and `state`.
5. The diagnostic loop was broken: the failing field was discarded in production,
   so fixes shipped on inference.
6. The failure surface is ambiguous: a 404 and a parse failure render identically.
7. The state rename has no data migration and reads reject the legacy values,
   turning legacy data into both 404s and enum failures.
8. Deployment skew reproduces "no change" with no code defect (a pinned image or a
   CDN/browser-cached SPA bundle) and must be excluded before assuming one.

## Enforced now, and what remains

At the boundary:

- Failures self-report. `gracefulParse` names the failing path in its message and
  in a searchable `schemaField` tag (field paths and codes only — never values).
- The receipt leaks are closed. `expiration_in_seconds` and the
  `previewed`/`revealed`/`burned`/`shared` timestamps are coerced; `expiration`
  is nullable, matching a consumed receipt that has no live secret to expire.
- Load failures no longer masquerade as consumption. `BaseShowSecret` shows a
  distinct, retryable error for any non-404 failure (network, 5xx, schema parse)
  and reserves the "viewed or expired" view for a genuine 404; `useSecret` records
  the status code that drives the split.

Open: the `viewed→previewed` / `received→revealed` rename still has no data
migration, and `Secret#viewable?` and the enums reject the legacy values. A secret
previewed on a pre-rename build is bricked to a 404, and a pre-rename receipt
fails the enum — the one remaining path from legacy data to the symptom. Closing
it needs the migration under `migrations/` plus legacy-tolerant reads until it has
run everywhere; it is deferred because it changes whether a secret can be shown.

Diagnosing a live instance: `schemaField` now identifies the field directly. At
rest, `HGET secret:<objid>:object lifespan` distinguishes a JSON number
(`604800`) from a poisoned JSON string (`"604800"`), and
`scripts/diagnostics/detect_string_typed_numerics.rb` scans the keyspace. A
symptom that survives the patched build with no schema error indicates deployment
skew, not a code defect.

## The systemic cure

Per #3496 / #3514: contracts as the single model definition, generating both
storage and shape JSON Schemas; validate `to_h` pre-save and `safe_dump`
pre-response with Familia's schema validation, so drift is a build failure rather
than a production incident and generated coercion replaces every hand cast,
including the ones above. The minimum that closes #3424 is that plus the state
migration; per-field casting alone cannot, by construction.

## References

- Issues/PRs: #3424, #3268, #3299, #3434, #3477, #3494, #3496, #3514
- Backend: `apps/api/v2/logic/secrets/{show_secret,show_receipt,list_receipts}.rb`,
  `lib/onetime/models/secret/features/{safe_dump_fields,secret_state_management}.rb`,
  `lib/onetime/models/receipt/features/safe_dump_fields.rb`
- Frontend: `src/schemas/contracts/{secret,receipt}.ts`,
  `src/schemas/shapes/v3/{secret,receipt}.ts`,
  `src/schemas/transforms/from-number.ts`, `src/utils/schemaValidation.ts`,
  `src/services/diagnostics.service.ts`,
  `src/shared/composables/useSecret.ts`,
  `src/shared/components/base/BaseShowSecret.vue`
- Authoritative failure enumeration:
  `src/tests/contracts/issue-3424-failing-field-forensics.spec.ts`
