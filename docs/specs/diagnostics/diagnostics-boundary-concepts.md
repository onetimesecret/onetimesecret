# docs/specs/diagnostics/diagnostics-boundary-concepts.md

## created: 2026-08-22

# Salvage inventory: feat/diagnostics-privacy-boundary (PR #4250)

Written 2026-08-22 before closing the branch. Branch HEAD: `ec13c729a6` (24 commits,
~12.5k insertions over 67 files, based on main). The operational slice was already
extracted to **PR #4250** (`feat/diagnostics-signal-quality`); everything below is
what did NOT get ported.

**Before deleting the branch**, tag it so every slice stays recoverable:

```bash
git tag archive/diagnostics-privacy-boundary ec13c729a6
git push origin archive/diagnostics-privacy-boundary
```

## Already ported (PR #4250) — do not re-port

- `lib/onetime/utils/diagnostics_ref.rb` + `try/unit/utils/diagnostics_ref_try.rb`
- `DiagnosticsSerializer` + bootstrap `diagnostics_ref: {user_ref, user_scope}` wire key
- Frontend user context (`actorContext.ts` — supersedes the branch's `actorIdentity.ts`)
- Backend Sentry user attribution (error_handler, base controller, v1 helpers)
- `grouping.ts` beforeSend rules (schema name; method+route+status)
- Colonel `get_organization_detail.rb` `organization_ref` emission (backend side)
- `.env.example` / `.env.reference` additions

## Unported slices, in port-priority order

Port each ON TOP of #4250, not from the branch state — `enableDiagnostics.ts`,
`beforeBreadcrumb.spec.ts`, `beforeSend.spec.ts`, and `createDiagnostics.spec.ts`
diverged in #4250 and will need manual merges. `actorIdentity.ts` and its spec are
superseded by `actorContext.ts`: never port them.

### 1. Schema-issue projection + failing-field fix

The value-free rendering of a ZodError: emits metadata about a parse failure
(schema name, path shape, issue code) while structurally refusing payload-derived
values (`issue.message`, `unrecognized_keys` — a real test leaked
`authorization_token` that way). Directly feeds #4250's group-by-schema-name rule
and closes the issue-3424 "which field failed" forensics gap.

- `src/utils/diagnostics/schemaIssueProjection.ts` (895 lines) — commit `aaaf7f7afb`
- `src/utils/schemaValidation.ts` (+334) — failing-field reporting, commit `d27f8e9383`
- Consumers switched off raw ZodError logging: `src/shared/stores/localReceiptStore.ts`,
  `src/services/incomingConfig.service.ts` — commit `418ad3f41e`
  ("fix(stores): log the schema-issue projection, not the raw ZodError")
- Specs: `schemaIssueProjection.spec.ts` (704), `schemaValidation.spec.ts` (505),
  `issue-3424-failing-field-forensics.spec.ts` (+248), `localReceiptStore.spec.ts` (+96)
- Layer rule pinned in file headers: `src/utils/diagnostics/` is pure policy — no
  imports from `@sentry/*` or `src/plugins/`.

### 2. apiRouteContext + axios parameterized route

Records the PARAMETERIZED route (`/api/colonel/organizations/:org_id`), never the
resolved URL, on every diagnostics surface. #4250's grouping already keys on
method+route+status; this slice is the richer producer (per-request route context
on schema-validation events, wiring claims tested).

- `src/utils/diagnostics/apiRouteContext.ts` (447 lines) — commit `aaaf7f7afb`
- `src/plugins/axios/interceptors.ts` (+116) — commit `ec51aae0e0`
- Specs: `apiRouteWiringClaims.spec.ts` (60), `interceptors.spec.ts` (+143)

### 3. breadcrumbPolicy — metadata-only breadcrumbs

Per-category key ALLOWLISTS (with type checks) for `xhr`/`fetch`/`navigation`
breadcrumbs; free-text scrub pass for every other category. Allowlist chosen over
denylist because `breadcrumb.data` is an open record written by SDK
instrumentation, our interceptors, and any `addBreadcrumb()` call.

- `src/plugins/core/diagnostics/breadcrumbPolicy.ts` (291 lines) — commit `ccbefe08e5`
- `enableDiagnostics.ts` wiring (the "pinned privacy boundary" portions of the +466
  in `ccbefe08e5`) — **highest merge-conflict risk vs #4250**
- Specs: `beforeBreadcrumb.spec.ts` (+277), `beforeSend.spec.ts` (+106),
  `createDiagnostics.spec.ts` (+225)

### 4. Free-text shape scrubbing (opaque identifier patterns)

Scrubs free text reaching diagnostics BY SHAPE (opaque identifiers, secrets-like
tokens) rather than by known key name. Complements the existing email/URL scrubbers.

- `src/utils/diagnostics/scrubbers.ts` (+216 of its +227 delta) — commit `f76869fa61`
- Specs: `opaqueIdentifierPatterns.spec.ts` (209), `scrubSensitiveStrings.spec.ts` (+105)

### 5. Scrubber consolidation move (mechanical)

Moves `src/plugins/core/diagnostics/{scrubbers,urlScrubbing}.ts` →
`src/utils/diagnostics/` under the pure-policy layer rule. ~20 files of import-path
churn, plus the corpus-path fix from `a1d3513273`
(`try/unit/utils/email_redaction_corpus_try.rb`, `tests/fixtures/email_redaction_corpus.json`).
Commit `aa7057bb6b`. Port together with slice 4 or skip until a quiet window —
pure churn, easy conflicts.

### 6. Registries

- `src/utils/diagnostics/safeFieldRegistry.ts` (290) + `safeFieldRetention.spec.ts` (137)
  — the explicit allowlist of fields permitted to reach diagnostics.
- `src/utils/diagnostics/resourceRefRegistry.ts` (254) + `resourceRefRegistry.spec.ts` (397)
  — pseudonymous resource references beyond user/org.
- Both from `aaaf7f7afb`. Value is real but they only pay off once slices 1–3 exist
  to consume them.

### 7. Leak-test batteries (acceptance)

Portable mostly as-is once their subjects land; they encode the boundary CONTRACT:

- `diagnosticsBoundary.spec.ts` (1011 lines, end-to-end acceptance) — commit `6835916d4f`
- `organizationRefLeakage.spec.ts` (371)
- `diagnosticsSurfaceClaims.spec.ts` (249), `collectionChildLiterals.spec.ts` (192)
- `src/tests/services/diagnostics.service.spec.ts` (+24)

### 8. Frontend colonel organization_ref schema

Backend emission shipped in #4250, but the frontend response schema did not:
`src/schemas/api/internal/responses/colonel-organizations.ts` (+29) — commit
`84f84a1d60`. Small, closes the loop on colonel org attribution. Check whether
#4250's backend spec asserts a shape the frontend schema must mirror.

### 9. Docs + changelog

- `docs/architecture/diagnostics-privacy-boundary.md` (622 lines) + README link —
  commit `560f673abb`. The reference doc several file headers cite
  (`REFERENCE: docs/architecture/diagnostics-privacy-boundary.md`); if slices 1–3
  port, this should follow, trimmed to match what actually shipped.
- `docs/development/{backend,frontend}-diagnostics.md` edits (small).
- `changelog.d/20260820_134500_claude_sentry_diagnostics_boundary.rst` — stale as a
  whole-branch fragment; write fresh fragments per ported slice instead.
- `lib/onetime/initializers/setup_diagnostics.rb` 6-line tweak (from `aa7057bb6b`) —
  inspect before porting; may be rename-only.

### 10. telemetry→diagnostics rename sweep — deliberately dropped

Commits `992f554996`, `24067377c7`, `1e0e75aa9b`, parts of `aa7057bb6b`. #4250
established its own naming (wire keys `user_ref`/`user_scope`; code-level actor
mechanism per `67656f13e4`). Re-doing a tree-wide rename from the archived branch
would fight it — if a rename is ever wanted, do it fresh against then-current main.

## Suggested port order

1 (projection + failing field) → 2 (route context) → 3 (breadcrumbs) as one to three
small PRs, each carrying its own specs from slice 7; then 4+5 together; 6, 8, 9
opportunistically. Each slice is independently shippable; none blocks #4250.
