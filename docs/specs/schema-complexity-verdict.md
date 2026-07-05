# Schema complexity: verdict and reduction plan

Third companion, closing the pair: `schema-problem-space.md` (the map) and
`schema-source-of-truth.md` (the cure, #3496/#3514). Those documents describe
and propose; this one *reviews* — every load-bearing claim was re-verified
against `develop` (7f8208c, 2026-07-05), the layers are graded for genuine
over-engineering versus necessary structure, and the open questions are
answered with recommendations. Prompted by the suspicion that the Zod v4
schema system is over-engineered.

## Verdict in one paragraph

The suspicion is half right, and it points at the wrong half. The
intellectual core — contracts, shapes, transforms (98 files) — is *not*
over-engineered: derivation is real and disciplined (`.extend()` for
entities, `augment()` for config), duplication is confined to the V2
state-alias widening and one standalone V1 file, and every invariant the
problem-space doc lists actually holds. The mountain feeling comes from the
`api/` layer (165 files, 5,378 lines), and there the feeling is justified:
roughly 80% of request files and 55–65% of response files are pure envelope
mechanics, a third of the layer (v1 + v2, ~54 files) has **zero** SPA
consumers, and the stores consume a coarse `responseSchemas` registry —
so the one-file-per-endpoint granularity buys the runtime nothing. Meanwhile
the actual defect — two unbridged lineages — costs production incidents and
is *cheaper to fix than assumed*: every Familia API the cure spec depends on
already ships in the pinned gem version. Fix the bridge first (it is wiring,
not construction), then collapse the api fan-out (it is deletion, not
redesign).

## Verification results

Claims from the two reports checked against the codebase and upstream:

| Claim | Verdict | Evidence |
|---|---|---|
| Inventory: 283 files, layer counts | holds (284 today) | contracts 44, shapes 50, api 165, ui 5, transforms 4, utils 4 |
| `api/` is mostly mechanical | holds, now quantified | 102 request files (1,991 lines, ~80% mechanical), 51 response files (2,999 lines, ~55–65% mechanical), 30 barrels; the two `base.ts` envelope factories are called 82 times across 18 files |
| Contracts→shapes is derivation, not duplication | holds | `shapes/v3/secret.ts:37-55` is `secretBaseCanonical.extend({…transforms})`; 19 of 20 `shapes/config` files derive via `augment()`; V1 is the sole standalone file |
| Registry covers 17–18 of ~90 entity schemas | holds, by design | `registry.ts:74-106`: 10 shapes + 5 api/v3 + 2 config, deliberately V3-scoped; 466 exported schema consts total, most are sub-schemas that should never be top-level outputs |
| Familia `schema_validation` infrastructure exists | **confirmed against the released gem** | familia 2.10.1 (the pinned resolution, `Gemfile.lock:88`) ships `features/schema_validation.rb`, `schema_registry.rb`, `Familia.schema_path`, `Familia.schema_validator` (defaults to `:json_schemer`). Verified in the extracted rubygems artifact, not just upstream main |
| Nothing wires it up in OTS | holds | no `schema_path`/`schema_validation` in `boot.rb`, config, or any model |
| No state migration exists | holds | `migrations/` has four dated dirs, none touch `state`/`viewed`/`received`; the "MIGRATION SCRIPT REQUIREMENTS" comments in both safe_dump files describe a script never written |
| `_receipt_attributes` merge bypasses safe_dump | holds, **and has a worse twin** | `apps/api/v2/logic/secrets/show_receipt.rb:250-252` merges raw `secret_state`; `apps/api/v1/logic/secrets/show_receipt.rb:192-195` does the same **and** skips the `.to_i` on `expiration_in_seconds` that v2 has |
| Ruby reads generated schemas for config only | holds | `operations/config/validate.rb:101` (static), `billing/operations/catalog/validate.rb:52` (billing); nothing reads `generated/schemas/shapes/` or a storage tree |
| #3496 closed = implemented | **false** | #3496 was closed by merging the spec document (#3514). Phases 1–4 have not landed; Phase 0 (observability) shipped separately per the RCA doc |

New defects found during verification, none previously documented:

- **`shapes/v1/secret.ts` is a receipt schema.** Its header comment says
  `shapes/v1/receipt.ts`, it exports `v1ReceiptSchema`/`V1Receipt`, and its
  only consumer is `api/v1/responses/secrets.ts:16`. There is no v1 secret
  shape. Rename the file.
- **`contracts/config/section/brand.ts` is orphaned.** No shape derives from
  it, nothing imports it directly; it is reachable only through the barrel
  wildcard. Delete or wire it.
- **The v1 `show_receipt.rb` raw merge is less guarded than v2's** (above).
  Any Phase 2/3 work that fixes v2 must fix v1 in the same commit.
- **`domains/responses/email-config.ts:45-73`** contains three byte-identical
  `createApiResponseSchema(...)` wrappers for get/put/patch.
- **Inconsistent envelope usage:** `organizations/responses/organizations.ts:17-30`
  and the internal surface hand-roll `{ record }` / `{ records, count }`
  inline, re-implementing exactly what the `base.ts` factories provide.

One correction to the cure spec that changes an implementation detail:

- **Phase 2's pre-response hook is at the wrong layer as written.** The spec
  says "validate `safe_dump` against the shape schema before response." But
  the TS contract's full receipt record already models the *merged endpoint
  payload* — `secret_state`, `expiration`, `expiration_in_seconds`,
  `natural_expiration` (`contracts/receipt.ts:232-239`) are fields that only
  exist after `_receipt_attributes` merges them in. Validating raw
  `safe_dump` output against that schema either fails on the missing fields
  or, if they are optional, lets the exact #3424 merge path escape again.
  Pre-response validation must run on the **final payload the logic class
  returns**, at the point `success_data` is built — not inside `safe_dump`.
  (Pre-save `to_h` validation is unaffected.)

## Layer-by-layer grades

| Layer | Files | Grade | Action |
|---|---|---|---|
| `contracts/` | 44 | sound | keep; delete the `brand.ts` orphan |
| `shapes/` v2+v3+domains+config | 48 | sound | keep; the derivation discipline is the system's best property |
| `shapes/v1/` | 2 | mislabeled | rename `secret.ts`→`receipt.ts`; keep while the Ruby v1 app is served |
| `transforms/` | 4 | sound | keep; this is exactly the right size for the version×encoding matrix |
| `utils/` | 4 | sound | keep; `augment()` is load-bearing for all 16 config shapes |
| `ui/` | 5 | sound | keep |
| `api/` v3, domains, organizations, auth, internal, invite, incoming, account | ~111 | **bloated** | collapse mechanical files into registry modules (below) |
| `api/` v1 + v2 | ~54 | **zero runtime consumers** | keep only what the OpenAPI generator enumerates; mark the layer documentation-only |
| `registry.ts` + generator | 2 | sound | add a convention-scoped CI check, not auto-registration |

The config parallelism (`contracts/config` types vs `shapes/config`
defaults+constraints) looks like duplication but is not: merging the trees
would force loose API-response consumers to carry validation defaults,
destroy `augment()`'s purpose, and surface the name collisions the selective
barrel currently avoids. Leave it; document it once at the top of each tree.

## The api/ layer: what to actually do

Evidence for collapsibility:

- Stores consume the layer through coarse registries —
  `gracefulParse(responseSchemas.secret, …)` (`secretStore.ts:109`) — not
  per-file imports. The per-endpoint files serve the OpenAPI generator and
  `schema-scanner.ts` (which iterate registry keys), not the runtime.
- The v1 and v2 TS surfaces have no frontend consumer at all; they feed
  `scripts/openapi/*` and `scripts/api-validation/*` exclusively. The Ruby
  `/api/v1` and `/api/v2` apps are still served, so the schemas earn their
  keep as *documentation* — but not as 54 separate files.
- Real per-endpoint logic is concentrated and identifiable:
  `auth/responses/auth.ts` (discriminated MFA/billing unions, type guards),
  `account/responses/colonel.ts` (admin records with transforms),
  `incoming/responses/incoming-secret.ts`, `invite/responses/show-invite.ts`,
  the domain-config request forms (`email-config.ts`, `sso-config.ts`), and
  the two `content/base.ts` files holding the layer's only `.refine()` calls.
  Roughly 8–10 files deserve to remain modules.

Plan, preserving every registry key (the tooling and store contract):

1. Per surface, replace the mechanical `responses/*.ts` +
   `requests/*.ts` + barrels with one `surface.ts` that builds the registry
   object directly: `secret: createApiResponseSchema(secretSchema,
   secretDetailsSchema), …`. Store call sites do not change.
2. Keep the 8–10 real-logic files as modules imported by their surface file.
3. Delete the re-export shims (`v2/responses/domains.ts`,
   `internal/responses/organizations.ts`) and the near-dead
   `invite/requests/*`.
4. Convert the hand-rolled envelopes in organizations/internal to the
   `base.ts` factories while touching them.
5. Expected end state: 165 files → ~35–45, −2,500 lines or more, zero
   behavior change, verified by the existing contract tests plus
   `pnpm run schemas:scan` and `openapi:generate` producing identical output.

This is deletion-shaped work. Do it *after* the bridge (next section) so the
backend validation lands against the current, well-tested layout, and so the
collapse has CI-level schema-sync checks watching it.

## Answers to the open questions

Numbering follows `schema-problem-space.md`.

1. **Which lineage wins?** TS contracts. Not because TypeScript is special,
   but because it is the only side with a schema language, a generator, and
   an interop format (JSON Schema) already flowing; Ruby has consumption
   infrastructure (json_schemer, Familia SchemaRegistry) but no authoring
   story. The neutral-third-artifact option buys language symmetry at the
   cost of a third lineage — the disease being cured. Decision already
   implicit in #3496; make it explicit and stop revisiting.
2. **Entity or endpoint payload as the unit of contract?** Both, explicitly.
   Entities stay the reusable core; every endpoint that merges computed
   fields must have its payload modeled (the full receipt record already is —
   `receiptRecordCanonical`). The enforcement is the corrected Phase 2 hook:
   validate the logic-class payload, which makes an unmodeled merge a
   validation failure instead of an invisible implicit shape.
3. **Can the api layer collapse?** Yes — see the plan above. The registry
   keys are the contract; the files are not.
4. **V1 retirement?** Decoupled and cheap. The TS v1 surface is 16 files
   serving documentation of a still-served Ruby app. Keep until the Ruby v1
   app sunsets (a product decision, not a schema decision); the carrying
   cost after the api collapse is one surface file plus the mislabeled shape.
5. **When does the state migration run?** It is the last open path to the
   #3424 symptom and it blocks Phase 2's raise-mode. Order: (a) Phase 3
   normalization at the emission boundary (known renames → canonical, unknown
   → logged fallback) ships first so reads tolerate legacy data; (b) the
   keyspace migration under `migrations/` runs second; (c) Phase 2 flips from
   warn to raise once the diagnostic scan is clean. The safe_dump comment
   blocks already specify the mapping — the script was just never written.
6. **Is all-or-nothing parsing right anywhere?** Only for fields where a
   wrong value is worse than no record: `state`, `has_passphrase`,
   identifiers, anything gating reveal/burn. Everything else should salvage
   per-field (Phase 5). Make the boundary explicit in the contracts —
   e.g. `.meta({ critical: true })` on the must-reject fields — so the
   salvage layer is driven by the schema rather than by a hand-kept list.
7. **Automatic registration?** No — 466 exports vs 17 curated entries means
   blanket auto-registration would emit hundreds of meaningless sub-schema
   files, and the curated keys are stable identifiers that Ruby and `bin/ots`
   depend on. Instead: a convention-scoped CI check asserting that every
   entity root in `shapes/v3/` and every `shapes/config` tree with a Ruby
   consumer is registered. Small allowlist, loud failure, no magic.

## Recommended sequence

1. **Bridge before beauty.** Land the cure-spec MVP — Phase 2 pre-save
   (warn), corrected Phase 2 pre-response on logic-class payloads, Phase 3
   state normalization, Phase 4 migration — for Secret and Receipt only.
   All of it is wiring: the gem features exist, the generator exists, the
   registry exists. Fix the v1 `show_receipt.rb` twin in the same change.
2. **Then collapse `api/`** per the plan above, with the schema-sync CI
   check (Phase 5) landing first so the collapse is provably behavior-free.
3. **Then the small hygiene items:** rename `shapes/v1/secret.ts`, delete
   the `brand.ts` orphan, dedupe `email-config.ts`, convert hand-rolled
   envelopes.
4. **Defer indefinitely:** merging the config trees (working as designed),
   replacing the datastore (correctly rejected as alternative H), any
   restructure of contracts/shapes/transforms (the part of the system that
   is pulling its weight).

## References

- Specs: `docs/specs/schema-problem-space.md`,
  `docs/specs/schema-source-of-truth.md`,
  `docs/specs/unviewable-state-root-cause.md`
- Issues/PRs: #3424, #3496, #3514
- Key evidence: `src/schemas/registry.ts`, `src/schemas/api/base.ts`,
  `src/schemas/shapes/v1/secret.ts` (mislabeled),
  `src/schemas/contracts/receipt.ts:232-239` (merged-payload fields),
  `apps/api/v2/logic/secrets/show_receipt.rb:250-252`,
  `apps/api/v1/logic/secrets/show_receipt.rb:192-195`,
  `src/shared/stores/secretStore.ts:109`, `scripts/openapi/schema-scanner.ts`
- Familia 2.10.1 (pinned): `lib/familia/features/schema_validation.rb`,
  `lib/familia/schema_registry.rb`, `lib/familia/settings.rb`
