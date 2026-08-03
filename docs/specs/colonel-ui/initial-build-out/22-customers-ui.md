---
labels: admin-v2, phase-1, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 20-ops-customers-extraction
epic: "#3653"
---

# Admin rebuild: Customers UI — filterable list + customer detail page (support without SSH)

## Context
Part of the Colonel Admin Rebuild epic. Phase-1 reference slice, UI half: the biggest UX upgrade in the plan. Today a support person does this by SSH; this gives them a customer list with real filters and a full customer detail page.

## Scope
- **Customers list** built on the admin UI kit DataTable + FilterBar (real server-side filters, index-backed pagination from #20) — replacing the hand-rolled `ColonelUsers.vue` table.
- **Customer detail page**: profile, plan, orgs, sessions, recent receipts, and an **action panel** (doctor, verify/unverify, change role/plan, purge) wired to the #20 colonel endpoints.
- Destructive actions (purge) go through the kit's typed **ConfirmDialog**.
- All data flows through the `useAdminCustomers` store (#12) + existing Zod `gracefulParse`.

## Grounding — files & pointers
- UI kit (from #11): DataTable, FilterBar, DetailDrawer, ConfirmDialog, StatCard, JsonViewer.
- Store (from #12): `useAdminCustomers` + shared paginated-fetch composable; validation via `gracefulParse` from `src/schemas/api/account/responses/colonel`.
- Endpoints (from #20): colonel role change / verify-unverify / purge / doctor, plus index-backed `List`/`Show`. Colonel API: `/api/colonel`, routes `apps/api/colonel/routes.txt`, handlers `apps/api/colonel/logic/colonel/*.rb`.
- Replace: `src/apps/colonel/ColonelUsers.vue:43-70` (hand-rolled table). Mine `src/apps/workspace/components/members/MembersTable.vue` and `src/apps/workspace/components/settings/{SettingsSection,SettingsPageHeader}.vue` for detail-page + settings-panel patterns.
- Lives under `src/apps/admin/` (URL stays `/colonel`), behind `experimental.admin_v2`.

## Acceptance criteria
- [ ] Customers list renders via DataTable + FilterBar with working server-side filters and pagination (no client-side load-all).
- [ ] Customer detail page shows profile, plan, orgs, sessions, recent receipts, and an action panel.
- [ ] Action panel performs doctor, verify/unverify, role change, plan change, and purge against #20 endpoints.
- [ ] Purge (and any destructive action) requires typed ConfirmDialog confirmation.
- [ ] All strings i18n'd; full `dark:` support; state via `useAdminCustomers` (no `colonelInfoStore.ts` dependency).
- [ ] **Phase-1 exit:** a support person can find a customer, run doctor, verify, and change a plan without SSH — each backed by the single #20 implementation.

## Notes / risks
- Every action button maps to a #20 op that enforces BOTH auth layers server-side; the UI never becomes the sole gate.
- Keep this a pure consumer of the kit + stores — no new bespoke tables or one-off fetch logic (that debt is what the rebuild removes).
