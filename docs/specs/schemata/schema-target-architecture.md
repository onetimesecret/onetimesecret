# Schema target architecture: one authority per projection

Companion to `schema-source-of-truth.md` (the cure spec, #3496/#3514): that
document says what to do; this one restates the problem from first
principles, records the rationale and evidence, and commits to a target
architecture chosen for the long-term health of the codebase and grounded
in what durable open-source projects actually do.

Two earlier working documents — `schema-problem-space.md` (the map) and
`schema-complexity-verdict.md` (the review) — are retired: their accepted
findings are folded into these two docs (the review's api/-layer collapse
plan is preserved verbatim in the appendix) and git history keeps the
originals. Citations of the review's numbered answers (Q1–Q7) refer to that
retired document.

Status: proposed. Verified against this tree (main, 2026-07-06), familia
2.11.2, otto 2.5.0, json_schemer 2.5.0. Executable evidence:
`docs/specs/schemata/proofs/emission_boundary_proof.rb` (12 asserted
expectations plus two informational reports — P5 timing, P6 drift status;
referenced below as P1–P6). The corrections below (Δ1–Δ4) are applied in
place in the cure spec.

## The problem, restated

The codebase does not have "a schema" per entity. It has **three
projections** of each entity, and the trouble comes from conflating them:

- **S — storage**: what Familia writes to and reads from Valkey.
  Field set: the model's `field` declarations, including storage-only fields
  the wire never sees (`org_id`, `receipt_viewed_at`, `secret_key`, `v1_*`).
- **W — wire**: what an endpoint emits, per API version. Field set:
  `safe_dump` output *plus* logic-class merges — computed fields (`is_*`,
  `shortid`, URLs) that are never stored.
- **A — application**: the post-parse types the SPA works with (`Date`,
  narrowed enums). Field set: W after transforms.

Each projection needs an authority, and the authority should sit with the
side that *produces* the data. Measured against that rule, the current
system has one healthy projection and two broken ones:

| Projection | Produced by | Authored by | Bridge | Verdict |
|---|---|---|---|---|
| A (application) | TS transforms | TS contracts/shapes | compiler + imports | healthy |
| W (wire) | Ruby `safe_dump` + logic merges | TS contracts/shapes | **discipline** | broken — every #3424-class bug lives here |
| S (storage) | Ruby Familia writes | **nobody** | — | absent — type-preserving storage, untyped fields (`FieldType` has no type option, familia 2.11.2 `field_type.rb:49`) |

Six structural defects follow, each with a specimen:

1. **The wire bridge is discipline, and discipline demonstrably fails.**
   `src/tests/contracts/receipt-safe-dump-fields.ts` says "Update this list
   when safe_dump_fields.rb changes." It is stale on this tree right now:
   `recipient_name` and `source` are missing (P6). The same failure mode at
   larger scale is #3424 itself.
2. **Storage accepts anything, forever.** A wrong-typed or out-of-enum value
   round-trips indefinitely; the supply of bad values is open-ended (ERB/ENV,
   YAML, console, raw HSET), so read-side enumeration of casts can never
   complete. This is root cause 1 of the RCA and it has no owner today.
3. **Ruby's wire projection is version-independent; the contracts are
   version-specific.** One `safe_dump` feeds V1, V2, and V3. Consequence:
   the V3 *wire* carries `viewed`/`received`/`is_viewed`/`is_received` today
   — the generated V3 schema merely tolerates them as additionalProperties
   (P3). The invariant "V3 never carries deprecated aliases" holds only
   after Zod strips unknown keys, not on the wire.
4. **The unit of wire contract is the endpoint payload, but Ruby's unit is
   the entity.** `generated/schemas/shapes/receipt.schema.json` already
   describes the *merged* payload — `natural_expiration`,
   `expiration_in_seconds`, the path/url fields are in `required`. A bare
   `safe_dump` record therefore *fails* the shape schema (P2): the merges in
   `apps/api/{v1,v2}/logic/secrets/show_receipt.rb` (v1 `:205-235`, v2
   `:268-312`; V3 inherits v2's unchanged), `base_secret_action.rb:55`
   (conceal/generate), and the `secret_value` injections in
   show_secret/reveal_secret are not decoration — they are the real wire
   shape, defined nowhere in Ruby as a shape.
5. **Renames run expand-forever.** `viewed→previewed`/`received→revealed`
   is expressed in six-plus places (stored legacy values, V2 widened enums,
   V3 exclusions, `deprecated_fields.rb`, safe_dump alias lambdas, the V1
   vocabulary) with no keyspace migration and no scheduled contraction. This
   is the expand phase of expand–contract with the contract phase never
   ticketed — the exact failure Fowler warns about in ParallelChange.
6. **Enforcement is inverted.** Nothing validates at write, nothing at
   emission; the only gate is the strictest one, all-or-nothing, in the
   client — the point farthest from the data, two languages and a network
   hop from the cause.

What is already right, and stays: the contracts→shapes→api derivation
discipline in TS; the registry + generator emitting draft 2020-12 JSON
Schema; config validation as the proof that Ruby-consumes-generated-schema
works; the Rhales hydration validator (`apps/web/core/application.rb:60-78`)
as in-repo precedent for pre-response validation; and — unused but decisive
— otto's response seam (below).

## Principles

Chosen for a 2–3 maintainer open-source project; each maps to practice that
has survived at Stripe, GitHub, Kubernetes, or GitLab.

1. **Producers publish machine-readable truth; consumers verify against the
   artifact; no hand-maintained mirrors.** Stripe generates its OpenAPI spec
   from the Ruby implementation and derives seven SDKs from it; GitHub's
   `rest-api-description` both validates production requests and powers
   contract tests. The pattern is not "spec-first" — it is *one canonical
   source per artifact, everything else generated and CI-gated*.
2. **Authority follows production.** The wire contract belongs where the
   consumer is (TS/Zod → generated JSON Schema — already flowing). The
   storage schema belongs to the writer (Ruby). "Which lineage wins?" was a
   false dichotomy: it wins *per projection*.
3. **Generated artifacts are checked in and drift-gated.** A generated file
   that isn't versioned and diffed in review is where these setups rot. The
   git diff of `generated/schemas/**` *is* the breaking-change gate
   (the JSON-Schema equivalent of `buf breaking`/oasdiff).
4. **Fail-closed at write, fail-open at emission, tolerant reader at
   consumption.** GitLab mandates json_schemer validation on every jsonb
   column write (fail-closed); committee/express-openapi-validator converge
   on response validation that raises in dev/test and logs in production
   ("spec drift shouldn't 500 a working response"); Fowler's Tolerant Reader
   governs the client, with an explicit carve-out for fields where a wrong
   value is worse than no record.
5. **Every rename is expand–contract with the contraction ticketed at
   expansion time.** GitHub and Stripe both classify added fields and added
   enum values as non-breaking and renames as breaking-requiring-a-version;
   for a self-hosted product the equivalent is a both-names window across at
   least one release, then a tracked contraction.
6. **Boring machinery only.** Checked-in JSON files, conformance assertions
   inside the test suites that already run, compiled-once validators. No
   Pact broker, no neutral IDL (TypeSpec/protobuf), no new formats — JSON
   Schema 2020-12 is already the lingua franca and is what OpenAPI 3.1
   embeds, so later OpenAPI publication is composition, not conversion.

## Target architecture

```
                    TS (Zod) — authority for W and A
  contracts/*.ts ──► shapes/v3, endpoint payloads ──► generated/schemas/**   (checked in, drift-gated CI)
                                                          │            ▲
                                            wire schemas  │            │  emission manifest
                                                          ▼            │  (safe_dump field lists)
                    Ruby — authority for S            Onetime::WireSchemas
  lib/onetime/models/<m>/storage.schema.json ─┐           │
        (hand-authored, co-located)           │           │ validate final payload
                                              ▼           ▼ at logic#response_data
  Familia feature :schema_validation      pre-save     emission        gracefulParse
        (validates to_h)                 fail-closed*  fail-open(prod)  tolerant+critical
                                                        fail-closed(CI)
  * after keyspace reconcile; warn until then
```

### W — wire schemas stay TS-authored; endpoint payloads become first-class

No re-architecture: contracts/shapes/transforms are the part of the system
pulling its weight. Two additions:

- **Every response a logic class emits must resolve to a registered
  schema.** The V3 logic classes already declare `SCHEMAS = { response:
  'receipt' }` — today consumed only by `scripts/openapi/schema-scanner.ts`.
  That constant becomes load-bearing: a convention-scoped CI check asserts
  every `SCHEMAS[:response]` name has a generated
  `api/v3/<name>-response.schema.json` (closes the registry-coverage gap for
  the surfaces that matter; blanket auto-registration stays rejected per the
  verdict's Q7).
- **Drift gate:** CI runs `pnpm run schemas:generate` and fails on a dirty
  `generated/` tree. Review of a schema-file diff is the breaking-change
  review.

### The emission boundary — the seam already exists

Otto 2.5.0's JSON response handler prefers a logic-provided payload over the
raw `process` result (`otto/response_handlers/json.rb:19-20`):

```ruby
data = if context[:logic_instance]&.respond_to?(:response_data)
         context[:logic_instance].response_data
```

No OTS class defines `response_data` — the seam is unused. There is no other
universal chokepoint: `V3::Logic::Base#success_data` is dead code (its one
subclass overrides without super), and `process` returns `success_data` only
by convention. The design therefore is:

- A `SchemaValidatedResponse` module for the API logic layer defines
  `response_data`: memoize `success_data`, look up the schema named by
  `SCHEMAS[:response]` in `Onetime::WireSchemas`, validate, return the
  payload. Classes without `SCHEMAS` are a CI failure on V3, tolerated on
  V1/V2.
- **`Onetime::WireSchemas`**: a small OTS registry that reads
  `generated/schemas/` via `manifest.json` at boot and holds
  compiled-once `JSONSchemer` instances. Compiled-once is mandatory:
  recompiling per call costs ~5× (P5). Wire schemas are keyed by registry
  key (`api/v3/receipt-response`), not by class name — this registry is
  deliberately separate from Familia's `SchemaRegistry`, which stays
  class-name-keyed for storage. One registry per projection, matching the
  authority split.
- **Failure mode**: raise in test/CI/dev; log + metric (Sentry tag
  `schemaField`, same taxonomy as Phase 0) in production. Emission
  validation never blocks a user response in production — permanently, not
  as a transition state. This is the committee/openapi-validator norm and it
  is the correct trade for a product whose payloads gate one-time reveals.
- **Schema-driven coercion replaces the hand casts** (cure Phase 3,
  sharpened): the coercion pass is derived from the wire schema's property
  types (`number` → `to_i`/`to_f` by whether the field is a sub-second
  timestamp, `boolean` → predicate, enum → normalize via the rename registry
  with logged fallback). Hand lambdas remain only where they encode business
  logic (`secret_identifier` gating, `obscure_email`, `is_*` derivations) —
  coercion and computation stop sharing a mechanism. Acceptance stays the
  cure spec's: removing any interim cast leaves output unchanged.
- **Per-surface projection (later)**: once conformance specs exist, V3
  emission filters the payload to the schema's properties, so the V3 wire
  stops carrying deprecated aliases (defect 3). V1/V2 keep emitting aliases
  by contract until sunset. This is a policy knob, not a precondition (P3).
- The v1 `show_receipt.rb` merge twin is brought under the same hook in the
  same change that covers v2/v3 (verdict finding).

The provider-side conformance specs are the contract tests: RSpec examples
that run the real logic classes over healthy, poisoned (string-typed TTL),
and legacy-state fixtures and assert the final payload validates against the
checked-in schema. That is the committee/`rest-api-description` pattern —
schema as executable contract inside the suite that already runs — and it
replaces the Pact-shaped machinery this team should not carry.

### S — storage schemas are Ruby-authored

The cure spec's Phase 1 (derive storage schemas from TS contracts) does not
survive contact with the field sets and is replaced (see Corrections, Δ1).
Instead:

- **Hand-authored JSON Schema per model, co-located with the model**:
  `lib/onetime/models/receipt/storage.schema.json`, describing the
  *canonical at-rest shape*: every persistent field, types, `state` as the
  canonical enum, `null` allowed wherever unset is legal (Familia's `to_h`
  includes nil-valued fields; `to_h_for_storage` omits them —
  `serialization.rb:24-27,61-64`). GitLab's mandatory `JsonSchemaValidator`
  on jsonb columns is the precedent: the writer declares what it writes,
  as a reviewed file, validated at write time.
- **Wired via `Familia.schemas` explicit mapping** (the convention loader
  capitalizes basenames and cannot produce `Onetime::Receipt`;
  `schema_registry.rb:92-97`), with `feature :schema_validation` enabled on
  `OT::Secret` and `OT::Receipt` first — the two models with incidents. The
  gem needs no changes for this (P4); a memoizing validator is injected via
  `Familia.schema_validator` (P5 proves the default recompiles per call and
  that injection works).
- **Mode**: warn until the keyspace reconcile completes, then raise —
  fail-closed at write is the end state (principle 4). Sequencing per the
  verdict's Q5: emission-side normalization ships first so reads tolerate
  legacy data; the `viewed→previewed`/`received→revealed` keyspace migration
  runs as a `Familia::Migration::Model` with `validate_before_transform?`/
  `validate_after_transform?` hooks (the gem's migration and
  schema-validation features are designed to compose); then pre-save flips
  to raise.
- **Anti-drift micro-bridge**: a spec asserting
  `storage.schema.json` properties == `Model.persistent_fields` (modulo
  declared exclusions). Twenty lines, kills the mini-dual-lineage between
  field declarations and schema file until Familia grows typed field
  declarations that *generate* the file (upstream follow-up).
- **Known residual, accepted**: fast-write methods (`field!`) and Lua CAS
  writes bypass `save`, so pre-save validation is not hermetic. The keyspace
  diagnostic (extended to any-field-out-of-schema, cure Phase 4) plus the
  migration framework covers at-rest truth; hermetic write validation would
  need a Familia-level hook and is not worth blocking on.

### A — consumption formalizes the tolerant reader

- Response schemas never `.strict()`; unknown fields are dropped, added enum
  values must not crash rendering (the GitHub/Stripe additive rule, read
  from the client side).
- The all-or-nothing failure mode is retained *only* for fields where a
  wrong value is worse than no record — `state`, `has_passphrase`,
  identifiers, anything gating reveal/burn — declared in the contracts via
  `.meta({ critical: true })` so the Phase 5 per-field salvage layer is
  schema-driven, not a hand-kept list. Zod v4 `.meta()` flows into the
  generated JSON Schema, so Ruby-side tooling can read the same flags.
- The hand mirrors (`src/tests/contracts/*-safe-dump-fields.ts`) are
  deleted once provider conformance specs land. If TS tests still want the
  backend field lists, they consume a generated **emission manifest** — a
  rake task dumping each model's `safe_dump_field_names` to
  `generated/emission/` — the producer publishing truth instead of a human
  transcribing it (principle 1, symmetric to wire schemas flowing TS→Ruby).

### Rename lifecycle — one registry, both sides

A single checked-in data file (e.g. `src/schemas/renames.json`) holding
each rename: canonical name, alias, scope (state value vs field name),
`deprecated_since`, and the release at which the contraction lands.
Consumers:

- Ruby emission: normalization of legacy stored values to canonical
  (logged), and alias emission on V1/V2 surfaces only.
- The keyspace migration generator (the mapping the safe_dump comment blocks
  have described since the rename — never executed).
- A TS test asserting the V2 widened enum equals canonical + registry
  aliases, replacing comment-based coordination.
- Docs/CHANGELOG tooling.

Creating an entry requires creating the contraction issue. That converts
defect 5 from "six expressions of one unfinished transition" into one
expression with an expiry date.

## Corrections to the cure spec (applied)

Folded into `schema-source-of-truth.md` on 2026-07-06 — its target
architecture and Phases 1–3 now state the corrected design directly. This
section stands as the rationale and evidence record.

- **Δ1 — Phase 1 as written is unsound.** Storage schemas cannot be derived
  from TS contracts by retyping timestamps: the field sets differ in both
  directions. For Receipt: storage-only fields the contract has never heard
  of (`org_id`, `domain_id`, `receipt_viewed_at`, `secret_value_shown_at`,
  `truncate`, `secret_key`, `v1_key`, `v1_custid`); wire-only fields that
  are never stored (`shortid`, `receipt_ttl`, `metadata_ttl`, all seven
  `is_*`, `show_recipients`, and the ten merged endpoint fields). A
  storage schema generated from `receiptCanonical` would either require
  fields that never exist at rest or say nothing about half of what does.
  Replaced by Ruby-authored storage schemas (above). This also dissolves the
  premise that TS must be the *single* source; it is the wire/application
  source.
- **Δ2 — the pre-response hook location, settled.** The verdict doc argued
  the hook must run on the final logic payload, not inside `safe_dump`; P2
  proves it (a faithful bare-`safe_dump` record fails the shape schema on
  nine required merged fields), and the investigation located the concrete
  seam: otto's `JSONHandler` → `logic#response_data`, currently unclaimed.
  `V3::Logic::Base#success_data` (dead) is removed as part of claiming it.
- **Δ3 — "generated coercion" gets a precise source**: the wire schema plus
  the rename registry, not "the schema" in the abstract; and coercion is
  separated from computed-field lambdas rather than replacing safe_dump
  wholesale.
- **Δ4 — registries split by projection.** Familia's `SchemaRegistry` for
  storage (class-name-keyed, `feature :schema_validation` validates `to_h`);
  an OTS `WireSchemas` registry for endpoint payloads (registry-key-keyed).
  P4 shows Familia's registry *could* hold both; it shouldn't — the keys
  answer to different authorities and different lifecycles.
- Unchanged and reaffirmed: Phase 0 observability (shipped), the Q5
  normalize→migrate→raise ordering, the api/-layer collapse deferred until
  the bridge lands, alternatives A–H as rejected.

## Enforcement matrix (end state)

| Boundary | Artifact | Mechanism | CI/dev/test | Production |
|---|---|---|---|---|
| TS internal | contracts/shapes | compiler + imports | fail | — |
| Generated tree | `generated/schemas/**` | regenerate + git diff | fail on drift | — |
| Registry coverage | `SCHEMAS[:response]` ↔ registry keys | convention-scoped check | fail | — |
| Pre-save (S) | `storage.schema.json` | Familia `feature :schema_validation` | raise | warn → **raise** after reconcile |
| Emission (W) | `api/v3/*-response.schema.json` | `response_data` hook + WireSchemas | raise | **log + metric, permanently** |
| Provider conformance | same wire schemas | RSpec fixtures: healthy/poisoned/legacy | fail | — |
| Field-list sync | emission manifest | generated, consumed by TS tests | fail | — |
| Storage↔model sync | schema vs `persistent_fields` | 20-line spec | fail | — |
| Read (A) | Zod shapes | gracefulParse: critical-strict, salvage rest | fail | salvage + `schemaField` tag |
| Keyspace | storage schemas | diagnostic scan + `Familia::Migration` | — | scheduled |

## Rollout

Ordering preserves the verdict's "bridge before beauty" and adds the
corrected storage track. Each stage is independently shippable.

1. **Seed the gates.** CI drift check on `generated/`; registry-coverage
   check; fix the stale receipt mirror (or jump straight to the emission
   manifest and delete it); land the proof script's fixtures as the first
   provider conformance spec.
2. **Emission MVP (closes the #3424 class).** `WireSchemas` +
   `SchemaValidatedResponse` on the V3 secret/receipt endpoints (warn-mode
   prod), state normalization via the rename registry, v1 twin included,
   conformance specs with poisoned/legacy fixtures.
3. **Storage track.** `storage.schema.json` for Secret and Receipt,
   `feature :schema_validation` pre-save warn, anti-drift spec, extended
   keyspace diagnostic, the state migration under `migrations/`, then flip
   pre-save to raise.
4. **Coercion consolidation.** Schema-driven coercion replaces the hand
   `to_i`/`to_f` casts (output-identical acceptance); V3 emission projection
   drops aliases from the wire; delete the TS mirrors.
5. **Then the deletions the review already approved:** api/ layer collapse
   behind the now-existing conformance gates (plan preserved in the
   appendix); hygiene items; OpenAPI 3.1 publication as an *output* artifact
   when wanted (oasdiff becomes available then, not before).

What the end state deletes — the payoff, in the currency of maintenance:
every hand cast in the safe_dump files, both `*-safe-dump-fields.ts`
mirrors, the "MIGRATION SCRIPT REQUIREMENTS" comment blocks (superseded by a
real migration), the dead `V3::Logic::Base#success_data`, and eventually the
alias emission itself (V2 sunset, contraction tickets already on file).

## Evidence

`bundle exec ruby docs/specs/schemata/proofs/emission_boundary_proof.rb` —
no Redis, no boot, gems from the lockfile only:

| # | Claim | Result |
|---|---|---|
| P1 | Emission validation names every #3424-class member precisely (`/state`, `/secret_ttl`, `/created`, `/secret_state`) | pass |
| P2 | Bare `safe_dump` fails the shape schema on exactly the nine required merged fields — the endpoint payload is the unit | pass |
| P3 | Deprecated aliases pass as additionalProperties — V3 wire carries them today; tightening is policy | pass |
| P4 | `Familia::SchemaRegistry` handles named wire schemas as-is; errors carry field pointers | pass |
| P5 | Default validator recompiles per call — asserted from the gem source; cost printed informationally (~5×); a caching validator injects via `Familia.schema_validator` | pass |
| P6 | The hand-maintained TS mirror was stale when written (`recipient_name`, `source` missing) — reported, not asserted, so the proof survives the mirror being synced or retired; the durable inverted gate belongs in CI | informational |

## Upstream follow-ups (nice, none blocking)

- familia: typed field declarations (`field :x, type: :integer`) generating
  the storage schema; memoized default `JsonSchemerValidator`;
  namespace-aware convention loading in `SchemaRegistry`.
- otto: none required — the `response_data` seam is sufficient as shipped.

## Deliberately not doing

Pact or any broker (one first-party consumer; conformance specs suffice); a
neutral third IDL (TypeSpec/protobuf — a third lineage is the disease);
auto-registration of all 466 schema exports; merging the config trees;
datastore replacement; re-typing contracts away from `z.date()` (the
generation roots are shapes and endpoint payloads, which express wire types
correctly; confining `unrepresentable: 'any'` remains a generator-hygiene
item, not an architecture one).

## Appendix: api/ layer collapse (preserved from the retired review)

Rollout stage 5's frontend reduction, kept here because the review that
approved it is retired. Evidence for collapsibility: stores consume the
layer through the coarse registries (`gracefulParse(responseSchemas.secret,
…)`, `secretStore.ts:109`), not per-file imports; the per-endpoint files
serve the OpenAPI generator and `schema-scanner.ts` (which iterate registry
keys), not the runtime. The v1/v2 TS surfaces have no frontend consumer at
all — they feed `scripts/openapi/*` and `scripts/api-validation/*`
exclusively, and earn their keep as *documentation* for the still-served
Ruby `/api/v1` and `/api/v2` apps, not as 54 separate files. Real
per-endpoint logic concentrates in ~8–10 files that deserve to remain
modules: `auth/responses/auth.ts` (discriminated MFA/billing unions, type
guards), `account/responses/colonel.ts` (admin records with transforms),
`incoming/responses/incoming-secret.ts`, `invite/responses/show-invite.ts`,
the domain-config request forms (`email-config.ts`, `sso-config.ts`), and
the two `content/base.ts` files holding the layer's only `.refine()` calls.

Plan, preserving every registry key (the tooling and store contract):

1. Per surface, replace the mechanical `responses/*.ts` + `requests/*.ts` +
   barrels with one `surface.ts` that builds the registry object directly:
   `secret: createApiResponseSchema(secretSchema, secretDetailsSchema), …`.
   Store call sites do not change.
2. Keep the ~8–10 real-logic files as modules imported by their surface file.
3. Delete the re-export shims (`v2/responses/domains.ts`,
   `internal/responses/organizations.ts`) and the near-dead
   `invite/requests/*`.
4. Convert the hand-rolled envelopes in organizations/internal to the
   `base.ts` factories while touching them.
5. Expected end state: 165 files → ~35–45, −2,500 lines or more, zero
   behavior change, verified by the existing contract tests plus
   `pnpm run schemas:scan` and `pnpm run openapi:generate` producing
   identical output.

This is deletion-shaped work. Do it *after* the bridge, so backend
validation lands against the current, well-tested layout and the collapse
has CI-level schema-sync checks watching it.

## References

- Living docs: `schema-source-of-truth.md` (the amended cure spec) and this
  one; retired (in git history): `schema-problem-space.md`,
  `schema-complexity-verdict.md`. Related:
  `docs/specs/recipient-disclosure/unviewable-state-root-cause.md`
- Proof: `docs/specs/schemata/proofs/emission_boundary_proof.rb`
- Seam: otto 2.5.0 `lib/otto/response_handlers/json.rb:19-27`;
  `apps/api/v3/logic/secrets.rb` (`SCHEMAS` constants);
  `scripts/openapi/schema-scanner.ts:292`
- Familia 2.11.2: `lib/familia/features/schema_validation.rb`,
  `lib/familia/schema_registry.rb`, `lib/familia/horreum/serialization.rb`,
  `lib/familia/migration/*`, `docs/schema-validation.md`
- Practice: Stripe API/OpenAPI generation and versioning
  (stripe.com/blog/api-versioning, github.com/stripe/openapi); GitHub
  rest-api-description and breaking-change policy; GitLab migration style
  guide (mandatory jsonb JsonSchemaValidator); interagent/committee;
  martinfowler.com — TolerantReader, ParallelChange; oasdiff/buf-breaking as
  the diff-gate genus; OpenAPI 3.1 ⊃ JSON Schema 2020-12
