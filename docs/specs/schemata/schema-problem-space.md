# Schema problem space

Companion to `schema-source-of-truth.md` (the proposed cure, #3496/#3514) and
`unviewable-state-root-cause.md` (what actually fails). Neither documents the
territory itself: what schema-like definitions exist, what each one is
authoritative for, which alignments are enforced by a machine and which by
discipline. This document is that map, against current `develop`. It proposes
nothing.

## Vocabulary

The codebase uses these words with specific meanings; conversations go wrong
when they blur.

- **Contract** (`src/schemas/contracts/*.ts`) — canonical field names and
  *output* types for an entity, version-independent, no wire transforms.
  "What the field is," not "how it arrives."
- **Shape** (`src/schemas/shapes/{v1,v2,v3,config,domains,organizations,…}/`) —
  a contract specialized to one wire encoding. V2 shapes layer string→type
  transforms over the contract (Redis-serialized strings on the wire); V3
  shapes layer number→Date transforms (native JSON types on the wire); V1
  shapes are standalone legacy vocabulary (`metadata_key`, `received`,
  `viewed`) and do not derive from contracts at all.
- **API schema** (`src/schemas/api/<surface>/{requests,responses}/`) — a shape
  wrapped in an envelope (`createApiResponseSchema`,
  `createApiListResponseSchema`) or a request payload definition. Nine
  surfaces: v1, v2, v3, domains, organizations, auth, internal, invite,
  incoming.
- **UI schema** (`src/schemas/ui/`) — local/session-storage and form schemas
  (e.g. `local-receipt.ts`), unrelated to any wire format.
- **Transform** (`src/schemas/transforms/`) — the `fromString` / `fromNumber` /
  `fromObject` converters that encode the V2-vs-V3 wire difference exactly
  once.
- **Generated schema** (`generated/schemas/*.schema.json`) — JSON Schema
  emitted by `src/schemas/scripts/generate.ts` from the registry
  (`src/schemas/registry.ts`) using zod v4 `z.toJSONSchema(…, { io: 'input' })`,
  so it describes the *wire* type (number, string), not the post-transform
  application type (Date).
- **Model fields** (Ruby, `lib/onetime/models/*.rb`) — Familia `field`
  declarations. Names only; Familia v2 has no `type:` option, storage is
  type-preserving.
- **safe_dump fields** (Ruby, `lib/onetime/models/*/features/safe_dump_fields.rb`)
  — the runtime serialization contract: an ordered list of fields plus
  optional per-field lambdas (`to_i`, `to_f`, state booleans, legacy aliases).
  This, not the model fields, defines what actually crosses the wire.

## Inventory

`src/schemas/` is 283 TypeScript files:

| Layer | Files | Role |
|---|---|---|
| `contracts/` | 44 | canonical entities + config sections (type-only) |
| `shapes/` | 50 | per-version / per-domain wire encodings |
| `api/` | 164 | request/response schemas across nine API surfaces |
| `ui/` | 5 | forms, notifications, layouts, local receipt |
| `transforms/` | 4 | wire-encoding converters |
| `utils/` | 4 | augment, feature flags, identifiers |
| root | 2 | `registry.ts`, `index.ts` |

`api/` is the bulk and most of it is envelope plumbing: the entity is defined
once in a shape, then re-wrapped per endpoint. The intellectual weight of the
system lives in the 94 contract+shape files; the 164 api files are mostly
mechanical derivation that still costs navigation and review attention.

The Ruby side adds, per entity: the Familia `field` list, the `safe_dump`
field array with hand coercions, and (Receipt) `deprecated_fields.rb` +
`migration_fields.rb` carrying the rename compatibility layer.

`generated/schemas/` currently holds 17 schemas + manifest: 10 shapes, 5 API
v3 request/response schemas, and 2 config schemas.

## One entity, end to end

A `Onetime::Secret` is expressed in at least ten places:

1. `lib/onetime/models/secret.rb` — Familia field declarations (names, no types)
2. `lib/onetime/models/secret/features/safe_dump_fields.rb` — 18 wire fields,
   coercion lambdas, legacy `is_viewed`/`is_received` aliases
3. `src/schemas/contracts/secret.ts` — canonical contract + state enum
   (`new, revealed, burned, previewed`)
4. `src/schemas/shapes/v1/secret.ts` — legacy vocabulary, standalone
5. `src/schemas/shapes/v2/secret.ts` — contract + string transforms + widened
   state enum (`+ received, viewed`)
6. `src/schemas/shapes/v3/secret.ts` — contract + number→Date transforms,
   deprecated aliases deliberately excluded
7. `src/schemas/api/{v1,v2,v3}/responses/secrets.ts` — envelope wrappers (3 files)
8. `src/schemas/api/{v2,v3}/requests/*` — conceal/generate/reveal/burn payloads
9. `generated/schemas/shapes/secret.schema.json` (+ `secret-details`,
   `secret-state`) — generated wire description
10. `generated/schemas/api/v3/secret-response.schema.json` — generated envelope

Receipt is worse: 40 safe_dump fields, plus `deprecated_fields.rb` (aliases
`viewed!`→`previewed!`), plus the single-record payload in
`apps/api/v2/logic/secrets/show_receipt.rb` that *merges* `safe_dump` output
with raw computed attributes (`_receipt_attributes`) — a second, implicit wire
shape defined nowhere in `src/schemas` and reachable by no coercion lambda
(the #3424 forensics enumerate the consequences).

## Where authority actually lives

The registry banner says contracts are canonical. That is true only inside
TypeScript. Across the whole system each concern has a different owner, and
the cross-language alignments are maintained by hand:

| Concern | Authoritative definition | Aligned with | By |
|---|---|---|---|
| Field names/types (TS) | `contracts/*.ts` | shapes, api | imports (machine) |
| Wire encoding per version | `shapes/v{1,2,3}` + `transforms/` | backend emission | discipline |
| What the backend actually emits | Ruby `safe_dump` arrays + logic-class merges | TS shapes | discipline |
| Storage shape | nothing (Familia is type-preserving) | — | — |
| State enum | `contracts/secret.ts` / `contracts/receipt.ts` | Ruby `secret_state_management.rb`, stored values | discipline; stored legacy values violate it |
| Config file shape | `shapes/config/*` (defaults + constraints) | `contracts/config/*` (types only) | discipline, documented as deliberate parallel |
| Generated JSON | registry (18 registered of ~90 entity schemas) | everything above | machine, but partial coverage |

Two structural facts fall out:

- **Every entity has exactly two independent sources of truth** — the TS
  contract lineage and the Ruby safe_dump lineage — connected by no generator,
  no validator, no test that runs both. Every #3424-class bug is a divergence
  between these two lineages surfacing at the strictest point (frontend
  `gracefulParse`).
- **The strictest gate sits at the point most distant from the data.** Nothing
  validates at write time (storage), nothing validates at emission
  (safe_dump/response), the frontend validates everything and rejects
  all-or-nothing. Errors therefore travel the maximum distance from cause to
  symptom, through two languages and a network hop, before detection.

## What is enforced vs. by convention

| Boundary | Mechanism | Status |
|---|---|---|
| YAML config at boot / CLI | `json_schemer` vs `generated/schemas/config/static.schema.json` (`lib/onetime/operations/config/validate.rb`, `apps/web/core/application.rb`); billing catalog likewise | enforced |
| Frontend API reads | `gracefulParse` per response schema | enforced, all-or-nothing |
| Frontend request payloads / local storage | zod at call sites, `ui/` schemas | enforced |
| TS internal consistency | compiler + imports | enforced |
| Ruby pre-save (`to_h`) | — | nothing |
| Ruby pre-response (`safe_dump`) | — | nothing (hand `to_i`/`to_f` on enumerated fields only) |
| Logic-class raw merges (`_receipt_attributes`) | — | nothing, and outside safe_dump's reach |
| Stored state values vs enum | — | nothing; legacy `viewed`/`received` persist, no data migration exists under `migrations/` (the `deprecated_fields.rb` aliases are write-path compat, not a keyspace migration) |
| Registry coverage | manual registration | 18 schemas registered; most api/ and all v1/v2 shapes unregistered |

## Complexity drivers

Ranked by how much of the mountain each one explains.

1. **Dual-lineage definitions with no bridge.** The TS side is internally
   coherent (contract → shape → api, machine-checked). The Ruby side is
   internally coherent (fields → safe_dump). Nothing checks one against the
   other; the generated JSON schemas exist and Ruby reads them for *config
   only*. This is the gap #3496/#3514 targets, and until it closes, every
   other driver below multiplies through it.
2. **Type-preserving storage.** Familia v2 round-trips whatever bytes were
   written. There is no schema at rest, so the supply of wrong-typed values is
   open-ended and every read boundary inherits the burden.
3. **Version × encoding matrix.** Three API versions with three wire
   encodings (V1 legacy vocabulary, V2 Redis-strings, V3 native JSON) means
   each entity legitimately needs three shapes. The transforms layer contains
   this well; the cost is real but structural, not accidental.
4. **The rename without a migration.** `viewed→previewed` /
   `received→revealed` lives simultaneously in: stored data (old values), V2
   shapes (widened enums), V3 shapes (excluded), Ruby aliases
   (`deprecated_fields.rb`), safe_dump legacy booleans, and the V1 mapping
   table. Six expressions of one unfinished transition.
5. **Implicit shapes in logic classes.** `ShowReceipt#_receipt_attributes` and
   friends define wire fields outside any schema file. These are invisible to
   both lineages and were the actual #3424 leak.
6. **Envelope fan-out.** 164 api files, largely mechanical. Not a correctness
   risk (machine-derived from shapes) but a major contributor to the *feeling*
   of a mountain and to onboarding cost.
7. **Deliberate config parallelism.** `contracts/config` (types) vs
   `shapes/config` (defaults + constraints) is documented and intentional, but
   it means "change a config field" touches two trees plus regeneration, and
   the distinction is easy to forget.
8. **Partial generation coverage.** The registry covers V3 + config. V2
   responses — the current public API — have no generated JSON schema, so any
   future backend-side validation can cover at most the surfaces someone
   remembered to register.

## Invariants worth writing down

These hold today and any redesign should either preserve them or consciously
break them:

- Contracts contain no transforms; encodings live only in shapes/transforms.
  (Holds; 37 of 50 shape files import from contracts, and the 13 that don't
  are v1 legacy, barrel indexes, or domain-specific shapes with no contract.)
- Generated JSON describes wire types (`io: 'input'`), never application types.
- The V3 surface never carries deprecated aliases; V2 always does.
- `safe_dump` output for numeric/timestamp fields is coerced and cannot fail
  the shape schema; `state` is the exception — emitted raw, gated only by
  enum membership at the reader.
- Config validation strictness lives in shapes, not contracts.

## Open questions

1. Which lineage wins? #3496 assumes TS contracts generate Ruby-side
   validation. The inverse (Ruby model as source, TS generated) or a neutral
   third artifact are not argued against anywhere; the choice is consequential
   and currently implicit.
2. What is the unit of contract: the entity, or the endpoint payload? The
   #3424 leak came from an endpoint composing entity + raw extras. If
   endpoint payloads aren't first-class in the contract system, logic-class
   merges will keep creating implicit shapes.
3. Can the 164-file api layer be generated or collapsed? It is already
   mechanical; the question is whether it should exist as files at all.
4. What is V1's retirement condition? It carries a whole standalone vocabulary
   whose only function is compatibility with v0.23 clients.
5. When does the state migration run, and what is legacy-tolerance policy at
   readers until it has run everywhere (per the RCA, the one remaining path
   from legacy data to the #3424 symptom)?
6. Is all-or-nothing parsing the right failure mode anywhere outside security
   -critical fields? (Phase 5 of the cure spec says no; the boundary between
   "salvageable" and "must-reject" fields is undefined.)
7. Registry coverage: should registration be automatic (fail CI on
   unregistered shape) rather than manual?

## References

- Specs: `docs/specs/schemata/schema-source-of-truth.md`,
  `docs/specs/recipient-disclosure/unviewable-state-root-cause.md`
- TS: `src/schemas/registry.ts`, `src/schemas/scripts/generate.ts`,
  `src/schemas/contracts/secret.ts`, `src/schemas/shapes/{v1,v2,v3}/secret.ts`,
  `src/schemas/transforms/index.ts`, `src/schemas/api/v3/responses/secrets.ts`
- Ruby: `lib/onetime/models/secret/features/safe_dump_fields.rb`,
  `lib/onetime/models/receipt/features/{safe_dump_fields,deprecated_fields,migration_fields}.rb`,
  `lib/onetime/operations/config/validate.rb`,
  `apps/api/v2/logic/secrets/show_receipt.rb`
- Generated: `generated/schemas/` (17 schemas + manifest)
