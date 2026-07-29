---
labels: admin-v2, phase-3, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Queue DLQ console (list / show / replay / purge)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — the operating-console payoff.

CLI-vs-UI gap this closes: dead-letter queue management (list / show / replay / purge) lives **only on `bin/ots`** (`lib/onetime/cli/queue/`, the `queue` group). There is already a queue-status widget and a `GetQueueMetrics` read endpoint in the admin surface — the DLQ console sits directly next to them, upgrading a read-only widget into an actionable one.

Recipe (uniform for all Phase-3 items): **extract op → add colonel route (BOTH auth layers) → screen on the UI kit.**

## Scope

- Extract DLQ list / show / replay / purge into operations, preserving CLI behavior bit-for-bit.
- Add colonel routes for each, guarded by BOTH auth layers.
- DLQ console screen on the kit, placed adjacent to the existing queue-status widget / `GetQueueMetrics` read view.
- **Purge** is destructive → typed-confirmation `ConfirmDialog`; dry-run default where the op supports it; replay + purge audit-logged (issue 21).

## Grounding — files & pointers

- CLI source of truth: `lib/onetime/cli/queue/` (`queue` group) — preserve behavior
- Existing read endpoint to sit beside: `apps/api/colonel/logic/colonel/get_queue_metrics.rb`
- Ops home: `apps/web/auth/operations/`; contract `lib/onetime/operations/README.md`
- Routes: `apps/api/colonel/routes.txt`; base logic `apps/api/colonel/logic/base.rb`
- Auth layers: `role=colonel` at Otto router + `verify_one_of_roles!(colonel: true)` in `raise_concerns`
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `DetailDrawer`, `JsonViewer`, `StatCard`, `ConfirmDialog` (typed confirmation)
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] DLQ list / show / replay / purge extracted into operations; existing CLI specs pass unchanged.
- [ ] Colonel routes added with BOTH auth layers.
- [ ] DLQ console screen renders next to the queue-status widget / `GetQueueMetrics`.
- [ ] Dead-letter payloads inspectable via `JsonViewer` / `DetailDrawer`.
- [ ] Purge gated by typed-confirmation `ConfirmDialog`; dry-run default if op supports it.
- [ ] Replay + purge recorded in the audit log (issue 21).
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Purge is irreversible message loss — typed confirmation and clear count-in-scope copy are mandatory.
- Replay can re-trigger side effects (emails, webhooks); default to dry-run and make live replay an explicit second step.
