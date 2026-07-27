---
labels: admin-v2, phase-2, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Domains screen (card grid + verify button)

## Context

Part of the **Colonel Admin Rebuild** epic. Phase 2 parity port; one PR.

CLI-vs-UI gap this closes: domain verification is a CLI-only chore today (`apps/api/domains/cli/verify_command.rb`), yet the `VerifyDomain` op **already exists with bulk support**. Surfacing a verify button on the domains screen is the cheapest CLI-parity win in Phase 2 — no extraction required.

## Scope

- Port the existing card-grid domains view onto the kit / domains store.
- Add a **verify** action that calls the existing `VerifyDomain` op (already bulk-capable) — this is the only capability beyond a straight port.
- Read side backed by `ListCustomDomains`.

## Grounding — files & pointers

- Current view to port: `src/apps/colonel/views/ColonelDomains.vue` (219 lines, card grid)
- Backend read: `apps/api/colonel/logic/colonel/list_custom_domains.rb`
- Verify op (exists, bulk-capable): `apps/web/` domains operations; CLI parity reference `apps/api/domains/cli/verify_command.rb`
- Routes: `apps/api/colonel/routes.txt`
- New app dir: `src/apps/admin/`
- Kit: `DataTable` / card layout, `DetailDrawer`, `FilterBar`, `ConfirmDialog`
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Domains list ports onto the kit + domains store with parity to `ColonelDomains.vue`.
- [ ] Verify action wired to the existing `VerifyDomain` op (single at minimum; bulk if the op surfaces cleanly).
- [ ] Loading via `closet/*Skeleton.vue`; icons via `OIcon`.
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.
- [ ] Old view untouched (fallback).

## Notes / risks

- Verify triggers real DNS/cert checks — surface op result symbols honestly (verified / pending / failed), don't fake success.
- Bulk verify is optional this PR if wiring one at a time is faster; the op supports both.
