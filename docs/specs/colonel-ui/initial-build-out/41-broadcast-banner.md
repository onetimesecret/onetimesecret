---
labels: admin-v2, phase-3, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Broadcast banner (set / show / clear)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — the operating-console payoff.

CLI-vs-UI gap this closes: the broadcast banner (set / show / clear) lives **only on `bin/ots`** (`lib/onetime/cli/` banner command group). Posting a maintenance notice today needs a deploy or SSH. This lets an operator publish maintenance comms from the browser.

Recipe (uniform for all Phase-3 items): **extract op → add colonel route (BOTH auth layers) → screen on the UI kit.**

## Scope

- Extract banner set / show / clear into operations, preserving CLI behavior bit-for-bit.
- Add colonel routes for each, guarded by BOTH auth layers.
- Banner screen on the kit: current banner display, set form (message/level), clear action.
- Clear is a destructive-ish verb → confirm; audit-logged (issue 21).

## Grounding — files & pointers

- CLI source of truth: `lib/onetime/cli/banner`, `lib/onetime/cli/banner_command.rb` (banner command group)
- Ops home: `apps/web/auth/operations/` (app-scoped); contract `lib/onetime/operations/README.md`
- Routes: `apps/api/colonel/routes.txt`; base logic `apps/api/colonel/logic/base.rb`
- Auth layers: `role=colonel` at Otto router + `verify_one_of_roles!(colonel: true)` in `raise_concerns`
- New app dir: `src/apps/admin/`
- Kit: `StatCard` / banner preview, form via `src/shared/components/ui/*`, `ConfirmDialog`
- Primitives: `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Banner set / show / clear extracted into operations; existing CLI specs pass unchanged.
- [ ] Colonel routes added with BOTH auth layers.
- [ ] Banner screen: shows current banner, sets a new one, clears.
- [ ] Clear action confirmed; set/clear recorded in the audit log (issue 21).
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Banner is user-facing globally — validate message length / allowed markup before publish.
- Preserve the CLI's notion of banner level/severity so CLI and UI render identically.
