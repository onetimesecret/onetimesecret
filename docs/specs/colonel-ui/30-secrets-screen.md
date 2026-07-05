---
labels: admin-v2, phase-2, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Secrets screen (list + receipt + guarded delete)

## Context

Part of the **Colonel Admin Rebuild** epic. Phase 2 = parity with the current colonel app on the new bones (UI kit + resource stores). Mechanical now that the kit and pattern exist; one PR.

CLI-vs-UI gap this closes: the current `ColonelSecrets.vue` is a 122-line hand-rolled table, and `DELETE /api/colonel/secrets/:secret_id` already exists in the backend but is **not wired into any UI** — deleting a secret today means the CLI or a raw API call. This screen surfaces that delete behind a guarded action.

## Scope

- Secrets list on the `DataTable` kit component, backed by the secrets Pinia store (shared paginated-fetch composable).
- Receipt detail in a `DetailDrawer` (uses `GetSecretReceipt`).
- Wire the **existing** `DELETE /api/colonel/secrets/:secret_id` into a destructive UI action gated by the `ConfirmDialog` typed-confirmation pattern.
- No new backend endpoints; delete route already exists.

## Grounding — files & pointers

- Current view to port: `src/apps/colonel/views/ColonelSecrets.vue`
- Backend logic: `apps/api/colonel/logic/colonel/list_secrets.rb`, `get_secret_receipt.rb`, `delete_secret.rb`
- Routes: `apps/api/colonel/routes.txt` (secrets, `secrets/:secret_id` DELETE)
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `DetailDrawer`, `ConfirmDialog` (typed confirmation), `JsonViewer`
- Primitives: `src/shared/components/ui/*`, `src/shared/components/modals/ConfirmDialog.vue`, `src/shared/components/closet/*Skeleton.vue`, `src/shared/components/icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Secrets list renders on `DataTable` via the secrets store + paginated-fetch composable.
- [ ] Receipt detail opens in `DetailDrawer` using `GetSecretReceipt`.
- [ ] Delete action wired to existing `DELETE /api/colonel/secrets/:secret_id`, gated by typed-confirmation `ConfirmDialog`.
- [ ] Loading states use `closet/*Skeleton.vue`; icons via `OIcon`.
- [ ] Zod response schemas under `src/schemas/api/account/responses/colonel`.
- [ ] Feature parity with `ColonelSecrets.vue`; old view untouched (kept as fallback).

## Notes / risks

- Delete is destructive and irreversible — typed-confirmation is mandatory, no bare confirm.
- Backend delete already exists and is guarded; this is a pure wiring/UI PR — do not modify the logic class beyond what parity needs.
