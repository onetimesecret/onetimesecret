---
labels: admin-v2, phase-2, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Organizations screen + billing-investigate workflow

## Context

Part of the **Colonel Admin Rebuild** epic. Phase 2 parity port. **Its own PR** — this is the hardest port and the one current view worth preserving mostly as-is.

CLI-vs-UI gap this closes: `ColonelOrganizations.vue` is 806 lines and the best screen in the current colonel app — it carries the billing-investigate workflow (`InvestigateOrganization`) and entitlement-override management (`ManageEntitlementOverride`). Rather than rebuild from scratch, port it onto the new bones while preserving its behavior.

## Scope

- Port the organizations list + investigate workflow onto the kit / organizations store.
- Preserve the billing-investigate flow (`InvestigateOrganization`, route `organizations/:org_id/investigate`) mostly as-is.
- Keep entitlement-override management (`ManageEntitlementOverride`).
- Budget as a standalone PR; do not fold into another screen.

## Grounding — files & pointers

- Current view to port (806 lines): `src/apps/colonel/views/ColonelOrganizations.vue`
- Backend logic: `apps/api/colonel/logic/colonel/list_organizations.rb`, `investigate_organization.rb`, `manage_entitlement_override.rb`, `set_entitlement_preview.rb`
- Routes: `apps/api/colonel/routes.txt` (`organizations`, `organizations/:org_id/investigate`)
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `DetailDrawer`, `StatCard`, `FilterBar`, `JsonViewer`, `ConfirmDialog`
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Organizations list on the kit + organizations store.
- [ ] Investigate workflow preserved and functional against `organizations/:org_id/investigate`.
- [ ] Entitlement-override management preserved (`ManageEntitlementOverride`).
- [ ] Investigate payload rendered via `JsonViewer` / `DetailDrawer` where the current view uses ad-hoc markup.
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.
- [ ] Old view untouched (fallback).

## Notes / risks

- Highest-effort port; 806 lines of billing logic — port behavior faithfully, defer refactors/improvements to a separate PR.
- Entitlement overrides mutate billing state — keep any existing confirmation guards; route through typed-confirmation `ConfirmDialog` if not already gated.
