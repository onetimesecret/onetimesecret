# docs/specs/schema-source-of-truth.md
---
# Schema as Single Source of Truth + Boundary Validation

Design spec for [#3496](https://github.com/onetimesecret/onetimesecret/issues/3496),
the systemic resolution of the [#3424](https://github.com/onetimesecret/onetimesecret/issues/3424)
class of bugs ("secret immediately shows 'no longer available' / marked previewed,
never viewable").

This document captures the diagnosis, the conspiring root causes, a phased
implementation plan, the alternatives considered, and acceptance criteria. It is
written so the plan can be executed (or argued with) without re-deriving the
investigation.

## Status

Proposed. No code changed by this document.

---

## 1. Problem statement

A recipient opens a secret link. The frontend calls
`GET /api/v3/guest/secret/:identifier`, the backend returns **HTTP 200** with a
valid record, but the frontend `gracefulParse(responseSchemas.secret, …)` fails,
so `record` stays `null` and the user sees "That information is no longer
available." The secret is never consumed; the sender dashboard shows "Previewed"
but never "Viewed."

Three rounds of fixes have shipped against this:

- **#3268** (proposal): `.to_i` casts in `safe_dump` lambdas.
- **#3434** (merged): cast numeric fields at the `safe_dump` boundary —
  `lifespan`/`secret_ttl` → `to_i`, `created`/`updated` → `to_f`.
- **#3477** (merged): write-boundary coercion in `Receipt.spawn_pair`, config TTL
  normalization, and reverting the contracts to strict non-null `z.number()`.

All three shipped in v0.25.11. The reporter confirms **no change** in behavior as
of 2026-06-22.

## 2. What we proved

1. **The numeric casts are airtight.** `safe_dump` emits `m.lifespan.to_i` /
   `m.secret_ttl → m.lifespan.to_i` (always `Integer`) and `m.created.to_f` /
   `m.updated.to_f` (always `Float`; even `nil.to_f == 0.0`). These four fields
   can no longer fail `z.number()` under any stored value.
   `lib/onetime/models/secret/features/safe_dump_fields.rb:56-65`, receipt
   `:75-81`.

2. **A fresh, healthy secret validates cleanly.** Reconstructing the exact
   `GET /api/v3/guest/secret/:id` payload
   (`apps/api/v2/logic/secrets/show_secret.rb:95-114`, serialized type-preserving
   via Otto `response=json`): every `record` field is either cast (numerics),
   method-computed to a real Boolean (`has_passphrase?`, `verification?`,
   `state?(…)`), or the in-enum string `state='previewed'`; every `details` field
   is forced to Boolean/Integer/nil by Ruby `!!`/`==`/arithmetic. **No field can
   fail the strict schema for a current, healthy record.**

3. **The recipient 200 path is guarded.** To return 200 (not 404), the backend
   requires `secret.viewable?` = `state?(:new) || state?(:previewed)`
   (`secret_state_management.rb:34`). So a legacy `state='viewed'` *secret* 404s
   — it never reaches a parse failure. The **receipt/dashboard list path has no
   such guard.**

4. **Familia cannot enforce types.** Storage is *type-preserving, not
   type-enforcing*: `serialize_value` → `Oj.dump`, `deserialize_value` →
   `Oj.parse`, with a rescue that returns the raw string on non-JSON bytes. There
   is **no** `field :x, type: Integer` / coerce / cast option in Familia 2.10/2.11.
   A string that leaks in at write time round-trips as a string forever. The
   `feature :schema_validation` + `SchemaRegistry` infrastructure exists but is
   **not wired up** in OTS and only *detects* (validates `to_h`); it does not
   coerce.

5. **The datastore is very unlikely to be implicated.** Redis, Dragonfly, Valkey,
   and KeyDB all return `HGET`/`HGETALL` values as byte-faithful bulk strings;
   none numeric-encode `HSET` values. RESP3 double/bignumber typing applies to
   score/coordinate/float commands, not hash field values, and Dragonfly defaults
   to RESP2. The reporter's use of Dragonfly v1.38.1 does not change the
   round-trip — the same stored bytes would reproduce on stock Redis. The
   corruption is write-time / data-provenance, not engine behavior. (See §7 for
   the cheap raw-bytes check.)

**Reframing:** the bug is a *class* of strict-type mismatches, not one field — and
crucially, **no one has ever captured the actual failing field**, because the
frontend discards it. Three fixes were shipped on inference.

## 3. Conspiring root causes

Each is a necessary condition; together they make the bug possible and recurrent.

1. **Type-preserving storage, no enforcement (Familia).** Any non-native value
   persists with its wrong type indefinitely; no per-field type guarantee.

2. **Open-ended set of string-injecting write paths.** ERB/ENV
   (`INCOMING_DEFAULT_TTL`), YAML floats, raw params. #3299 found two and #3477
   fixed two — but with no single choke point, the next leak is inevitable.

3. **A strict, frontend-authored contract used as an all-or-nothing gate.**
   `z.number()/z.boolean()/z.enum()` with zero coercion, and one bad field nulls
   the *entire* record → `UnknownSecret`. The schema was written to the idealized
   model, not to what `safe_dump` emits across the real keyspace (legacy `state`,
   older payloads missing newer canonical keys).

4. **Whack-a-mole remediation at the wrong layer.** Casting individual fields in
   `safe_dump` is correct but incomplete by construction. `state` is the one
   strict record field still read raw with no coercion
   (`safe_dump_fields.rb:38`), and the legacy `viewed→previewed` rename has **no
   data migration** — the "MIGRATION SCRIPT REQUIREMENTS" blocks in the safe_dump
   files are aspirational comments only.

5. **A broken diagnostic loop.** `gracefulParse` logs a generic string and puts
   the precise `error.issues[].path` into Sentry *extras* (non-searchable);
   `loggingService.error` receives a bare `Error` with no issues
   (`src/utils/schemaValidation.ts:79-90`, `diagnostics.service.ts:117-122`). No
   one — reporter or maintainer — has seen which field actually fails.

6. **An ambiguous failure surface.** `UnknownSecret` renders identically for a
   legitimate 404 (expired/consumed/legacy-unviewable) and a schema parse failure.
   The reporter reasonably assumed parse failure; some instances are likely 404s
   on legacy-state data.

7. **Version/data skew.** The receipt list path + legacy `state='viewed'/'received'`
   matches the dashboard symptom exactly. Helm chart pins an image and SPA bundles
   can be CDN/browser-cached, so frontend schema and backend payload can desync
   ("no change on v0.25.11" is also consistent with the running image/bundle
   simply not being v0.25.11).

## 4. Most-likely live explanations, ranked

1. **Receipt/dashboard payload rejects a legacy `state` enum value**
   (`'viewed'`/`'received'`) on the list endpoint — no viewability guard, emitted
   raw, no migration. Best fit for "Previewed but never Viewed."
   `src/schemas/contracts/receipt.ts:47-57,170`; `receipt/.../safe_dump_fields.rb:58`.
2. **The deployment isn't effectively running v0.25.11** (chart/image pin or
   cached SPA bundle) — simplest fit for "no change."
3. **The recipient "no longer available" is partly a 404** on legacy-unviewable
   records, conflated with the parse failure by the shared `UnknownSecret` view.
4. **A missing required key** (older server/bundle skew) — `z.object` rejects
   absent `is_previewed`/`is_revealed`.

## 5. Target architecture

```
src/schemas/contracts/*.ts   ── canonical model truth (Zod, no transforms)  ◄── SINGLE SOURCE
        │  z.toJSONSchema(io:'input', override)
        ├─► generated/schemas/storage/*.schema.json   timestamps→number   →  Familia validates to_h (pre-save)
        └─► generated/schemas/shapes/*.schema.json    wire projection      →  backend validates safe_dump (pre-response)
                                                                            →  frontend gracefulParse (already)
```

`to_h` (raw Ruby fields) is validated against **storage** schemas; `safe_dump`
(wire output) is validated against **shape** schemas. The frontend consumes the
same generated shapes it already does. Drift becomes a build failure, not a
production incident.

Design goals, each mapped to a root cause:

| Goal | Kills root cause |
|---|---|
| G1. One canonical model definition; backend & frontend types derived, never hand-aligned | #3, #7 |
| G2. Backend physically cannot emit a payload the frontend rejects (validate at the boundary) | #3, #4 |
| G3. Coercion generated from the contract, not hand-written per field | #4 |
| G4. The at-rest keyspace reconciled to the contract (incl. the `state` rename) | #4, #1 |
| G5. A single bad field never hides a viewable secret; failures self-report | #5, #6 |

## 6. Phased implementation

### Phase 0 — Make the failure visible (prerequisite)

Without this we keep guessing, which is how three fixes missed. Not optional even
for the systemic path — it is how we *prove* the fix closes #3424.

- `src/utils/schemaValidation.ts:79-90`: build the error message from
  `result.error.issues` (`path.join('.')` + `code` + `received`) and attach the
  joined paths as a searchable Sentry tag `schemaField` (register it in
  `diagnostics.service.ts:39 TAG_FIELDS`). Make `loggingService.error` carry the
  issues, not a bare message.
- Backend mirror: a sampled log when `safe_dump` output fails its shape schema
  (enabled by Phase 2), so operators see the field server-side even without Sentry.
- **Deliverable:** the reporter gets `records[N].state received "viewed"` instead
  of a generic string. Confirms which hypothesis is real before we build further.

### Phase 1 — Contracts as model source of truth + generate storage schemas

- Add `contracts/*` to the generation registry (`src/schemas/registry.ts`); today
  only shapes/API schemas generate (`scripts/json-schema/generate.ts`).
- Add a second generation target: a `toStorageJsonSchema()` pass whose `override`
  maps `z.date()` → `{ type: 'number' }` (epoch seconds, matching `to_h`) instead
  of the current `date-time` string (`generate.ts:68-77`). Output to
  `generated/schemas/storage/`; keep the wire output as `generated/schemas/shapes/`.
- The contract file does not change; the *generation target* decides number vs
  ISO string.
- **Acceptance:** `pnpm run schemas:json:generate` emits both `storage/secret.schema.json`
  and `shapes/secret.schema.json`; CI fails if they drift from the Zod source.

### Phase 2 — Wire Familia validation at both boundaries

- Add `json_schemer` to the Gemfile; in `lib/onetime/boot.rb` set
  `Familia.schema_path = OT.root/'generated'/'schemas'/'storage'` and
  `Familia.schema_validator = :json_schemer` (Familia otherwise falls back to a
  silent `NullValidator`).
- Enable `feature :schema_validation` + `schema 'secret.schema.json'` on
  `OT::Secret` and `OT::Receipt` (`lib/onetime/models/secret.rb:14-30`).
- **Two enforcement points** (this is the key refinement to #3496, which only
  addressed storage):
  1. **Pre-save:** validate `to_h` against the storage schema → blocks string
     TTLs / bad `state` from entering Redis. Start in warn/log mode; flip to raise
     after Phase 4.
  2. **Pre-response:** validate `safe_dump` output against the **shape** schema in
     the V3 logic base (or a tryout/CI gate) → this is the literal #3424 failure,
     caught on our side first.
- **Acceptance:** a tryout feeds a legacy `state='viewed'` record through both
  validators and they flag it; a healthy record passes both.

### Phase 3 — Generated coercion (eliminate whack-a-mole)

- Replace per-field hand casts with a coercion map derived from the storage/shape
  schema (field → JSON type). A small `SafeDump` coercion layer applies
  `to_i`/`to_f`/boolean/enum-normalization generically, so every field is coerced
  to its contract type — not just the numerics someone remembered.
- Fold `state` legacy normalization (`viewed→previewed`, `received→revealed`,
  unknown→safe canonical) into this layer for Secret and Receipt.
- **Acceptance:** removing a hand cast doesn't change output; adding a contract
  field auto-coerces with no safe_dump edit. The interim casts from #3434/#3477
  are deleted.

### Phase 4 — Reconcile the at-rest keyspace

- Write the missing migration under `migrations/<date>/` that rewrites
  `state='viewed'→'previewed'` and `'received'→'revealed'` for `secret:*` and
  `receipt:*`.
- Extend `scripts/diagnostics/detect_string_typed_numerics.rb` to also report
  out-of-enum `state` and any field failing the storage schema (rename to a
  general "schema drift detector"). Run on the reporter's two environments.
- Flip Phase 2 pre-save validation from warn → raise once the detector reports
  clean.

### Phase 5 — Make it permanent + resilient consumer

- **Fail-soft frontend:** if `gracefulParse` fails, attempt per-field salvage
  (coerce/drop the offending field) so a viewable secret is shown rather than
  nulled — and `UnknownSecret` distinguishes a true 404 from a parse failure.
- CI gates: schema-sync check, `safe_dump`-vs-shape contract test with **legacy
  fixtures** (today every test uses `state:'new'` — the gap that let this
  through), and a generated-types check.

**Minimum viable systemic change** = Phase 0 + 2 (pre-response validation) + 3
(`state` in the coercion layer) + 4 (migration). Phases 1 and 5 complete the
vision but the bug is closed by MVP.

## 7. Cheapest single diagnostic (run alongside Phase 0)

Pull the raw bytes of a failing record's field:

```
redis-cli -p <port> HGET secret:<objid>:object lifespan
```

- `"604800"` **with quotes** → written as a String upstream → engine exonerated;
  this is the write-boundary / legacy-data problem (Phases 2 + 4).
- `604800` **without quotes** → should round-trip as Integer on any store; if it
  still arrives as a String, that is the first real evidence of an engine quirk
  and warrants the cross-store round-trip script (Oj.dump → HSET → HGET → Oj.load
  against Redis vs Dragonfly vs Valkey, asserting the returned Ruby class under
  both RESP2 and RESP3).

## 8. Alternatives considered

**A. Keep casting fields in `safe_dump` as they surface (status quo).** Rejected:
provably whack-a-mole — `state` is already the next unguarded field, and Familia's
type-preserving storage guarantees a *next* one. This is the loop that produced
#3268 → #3434 → #3477 with the bug still open.

**B. Loosen the frontend schema (`z.coerce.*` / nullable+tolerant everywhere).**
Rejected as the primary fix (kept as the Phase 5 safety net): it permanently
abandons the type contract, hides real corruption, and the reverted
nullable-contract attempt in #3477 already showed the maintainer prefers enforcing
the invariant over relaxing it.

**C. Add typed fields to Familia (`field :lifespan, type: Integer`).** The cleanest
root fix for cause #1, but rejected for now: it requires upstream changes to the
`delano/familia` gem (the capability does not exist in 2.10.1), a release, and a
version bump. Worth proposing to Familia as a follow-up; the OTS-side coercion
layer (Phase 3) is the same idea implemented where we control it, and de-risks the
dependency.

**D. Enforce types only at the write boundary (the #3299 `spawn_pair` approach).**
Rejected as sufficient on its own: it can't heal the existing corrupt keyspace,
doesn't cover paths that bypass `spawn_pair` (console, raw HSET, future callers),
and doesn't catch wire-shape drift. Necessary but partial — folded into Phases
2/4.

**E. Validate only `to_h` against storage schemas (literal #3496 scope).**
Rejected as incomplete: #3424 is a wire-shape failure, and `safe_dump` ≠ `to_h`
(it renames, computes, and coerces). Validating only `to_h` would pass while the
wire payload still breaks the frontend. The plan adds the safe_dump-vs-shape check
that #3496 omitted.

**F. Server-side render / inline the secret payload to bypass the SPA schema.**
Rejected: large architectural change, loses the type-safety the contracts buy, and
doesn't address the dashboard/list symptom.

**G. Do observability only and wait for the field.** Tempting and cheap (it is
Phase 0), but rejected as the whole answer: it tells us which field, not why the
class keeps recurring. Prerequisite, not cure.

**H. Blame/replace the datastore (Dragonfly → Redis).** Rejected: research shows
all four Redis-compatible stores preserve hash-value bytes and reply types
identically on the relevant path; the round-trip is deterministic and the same
data reproduces on Redis. Store choice is not a variable here.

## 9. Risks & mitigations

- **Pre-save raise could reject writes on dirty data** → ship in warn mode, raise
  only after the Phase 4 detector is clean.
- **Generated-coercion behavior change** → land behind a contract test that diffs
  old vs new `safe_dump` output on a fixture corpus *including legacy states*.
- **`z.date()` dual-meaning confusion** → document the contract-vs-target
  convention; the override lives only in the generator.
- **Familia version**: the working checkout is 2.11.0 but OTS locks 2.10.1 —
  verify `schema_validation`/`SchemaRegistry` APIs against the locked gem before
  Phase 2.

## 10. Acceptance criteria (tied to #3424)

1. Phase 0 yields the real `issues[].path` for a failing payload.
2. A legacy `state='viewed'` record is (a) flagged by the detector, (b) rejected
   by pre-save validation, (c) normalized by the coercion layer so the wire
   payload validates, and (d) rewritten by the migration.
3. A representative ShowSecret **and** ListReceipts payload — built from real
   `safe_dump`, including legacy fixtures — passes the generated shape schema in CI.
4. Removing any interim `to_i`/`to_f` cast leaves output unchanged (coercion is
   now generated).
5. The frontend renders a viewable secret even if one non-essential field is
   malformed.

## 11. References

- Issues/PRs: #3424, #3268, #3299, #3434, #3477, #3496
- Backend: `lib/onetime/models/secret/features/safe_dump_fields.rb`,
  `lib/onetime/models/receipt/features/safe_dump_fields.rb`,
  `apps/api/v2/logic/secrets/show_secret.rb`, `apps/api/v3/logic/secrets.rb`,
  `lib/onetime/models/secret/features/secret_state_management.rb`,
  `lib/onetime/models/receipt.rb` (`spawn_pair`), `lib/onetime/config.rb`
- Frontend: `src/schemas/contracts/secret.ts`, `src/schemas/contracts/receipt.ts`,
  `src/schemas/shapes/v3/secret.ts`, `src/schemas/api/base.ts`,
  `src/shared/stores/secretStore.ts`, `src/utils/schemaValidation.ts`,
  `src/services/diagnostics.service.ts`
- Generation: `scripts/json-schema/generate.ts`, `src/schemas/registry.ts`,
  `generated/schemas/`
- Familia: `lib/familia/horreum/serialization.rb`, `lib/familia/json_serializer.rb`,
  `lib/familia/features/safe_dump.rb`, `lib/familia/features/schema_validation.rb`,
  `lib/familia/schema_registry.rb`
