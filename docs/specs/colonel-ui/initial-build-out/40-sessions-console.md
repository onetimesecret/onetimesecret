---
labels: admin-v2, phase-3, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Sessions console (inspect / search / delete)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — beyond parity, the actual payoff. The UI stops being a dashboard and becomes an operating console. Phase-3 items are ordered by how often you reach for the CLI; **sessions is first** because session inspection is core incident response.

CLI-vs-UI gap this closes: session inspect/search/delete lives **only on `bin/ots`** (`lib/onetime/cli/session/`, the dry-cli `session` group) — no operation, no API, no UI. Incident response requires SSH today. This brings it into the browser.

Recipe (uniform for all Phase-3 items): **extract op → add colonel route (BOTH auth layers) → screen on the UI kit.**

## Scope

- Extract session inspect / search / delete into operations, preserving CLI behavior bit-for-bit.
- Add colonel API routes for each, guarded by BOTH auth layers.
- Sessions console screen on the kit: searchable/inspectable list, session detail drawer, delete action.
- Session **delete** is destructive → typed-confirmation `ConfirmDialog`; dry-run default where the op supports it; audit-logged (issue 21).

## Grounding — files & pointers

- CLI source of truth: `lib/onetime/cli/session/` (dry-cli `session` group) — preserve behavior
- Ops home: `apps/web/auth/operations/`; contract `lib/onetime/operations/README.md` (single `#call`, stateless, returns symbols / immutable `Data`)
- Routes: `apps/api/colonel/routes.txt`; base logic `apps/api/colonel/logic/base.rb`
- Auth layers: `role=colonel` at Otto router + `verify_one_of_roles!(colonel: true)` in `raise_concerns`
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `FilterBar`, `DetailDrawer`, `JsonViewer`, `ConfirmDialog` (typed confirmation)
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Session inspect / search / delete extracted into operations; existing CLI specs pass unchanged.
- [ ] Colonel routes added with BOTH auth layers (router `role=colonel` + `verify_one_of_roles!`).
- [ ] Sessions console screen: search, inspect (detail drawer), delete.
- [ ] Delete gated by typed-confirmation `ConfirmDialog`; dry-run default if op supports it.
- [ ] Destructive actions recorded in the audit log (issue 21).
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Deleting a session logs a user out mid-flight — confirm the exact target session in the dialog copy.
- Extraction must not change CLI behavior; op is the shared core, CLI and route both call it.
