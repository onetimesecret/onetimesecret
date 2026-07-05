---
labels: admin-v2, phase-3, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Domain toolbox (repair / orphaned-scan / probe / transfer)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — the operating-console payoff.

CLI-vs-UI gap this closes: the rich domain toolbox (repair / orphaned-scan / probe / transfer) lives **only on `bin/ots`** (`apps/api/domains/cli/`). The Phase-2 domains screen (issue 31) already added the cheap `VerifyDomain` win; this issue surfaces the heavier diagnostic/repair verbs. `VerifyDomain` also proves the extraction pattern for the rest.

Recipe (uniform for all Phase-3 items): **extract op → add colonel route (BOTH auth layers) → screen on the UI kit.**

## Scope

- Extract repair / orphaned-scan / probe / transfer into operations, preserving CLI behavior bit-for-bit.
- Add colonel routes for each, guarded by BOTH auth layers.
- Domain toolbox screen (or a toolbox panel on the Phase-2 domains screen) on the kit.
- **Transfer** and **repair** mutate ownership/state → typed-confirmation `ConfirmDialog`; dry-run default where the op supports it (probe / orphaned-scan are read-only); mutations audit-logged (issue 21).

## Grounding — files & pointers

- CLI source of truth: `apps/api/domains/cli/` — `repair_command.rb`, `bulk_repair_command.rb`, `orphaned_command.rb`, `probe_command.rb`, `transfer_command.rb`, `reconcile_sender_command.rb`, `verify_command.rb`, `helpers.rb`
- Existing op reference (already extracted, bulk-capable): `VerifyDomain` (see issue 31)
- Ops home: `apps/web/auth/operations/` / app-scoped domains ops; contract `lib/onetime/operations/README.md`
- Routes: `apps/api/colonel/routes.txt`; base logic `apps/api/colonel/logic/base.rb`
- Auth layers: `role=colonel` at Otto router + `verify_one_of_roles!(colonel: true)` in `raise_concerns`
- New app dir: `src/apps/admin/`; relates to issue 31 domains screen
- Kit: `DataTable`, `DetailDrawer`, `JsonViewer`, `ConfirmDialog` (typed confirmation), `StatCard`
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Repair / orphaned-scan / probe / transfer extracted into operations; existing CLI specs pass unchanged.
- [ ] Colonel routes added with BOTH auth layers.
- [ ] Toolbox screen/panel: probe + orphaned-scan (read-only), repair + transfer (guarded).
- [ ] Transfer/repair gated by typed-confirmation `ConfirmDialog`; dry-run default where the op supports it.
- [ ] Ownership/state mutations recorded in the audit log (issue 21).
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Transfer reassigns domain ownership across customers/orgs — highest-blast-radius verb here; confirm source + target explicitly.
- Reuse the `VerifyDomain` extraction as the template for the remaining commands to keep op shapes consistent.
