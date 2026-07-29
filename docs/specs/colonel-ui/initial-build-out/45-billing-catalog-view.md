---
labels: admin-v2, phase-3, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Billing catalog view (read-only drift)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — the operating-console payoff. Ordered last among Phase-3 items: lowest reach-for-CLI frequency, and deliberately read-only to start.

CLI-vs-UI gap this closes: catalog / plan drift is inspected via CLI today, though the catalog/sync operations **already exist** under `apps/web/billing/operations/`. This surfaces a **read-only drift view first** — sync stays CLI-only until the view is trusted. No mutating verbs this issue.

Recipe note: unlike the other Phase-3 items this needs **no op extraction and no mutating route** — the read ops exist; this is a screen-on-the-kit over an existing read path (`GetAvailablePlans` / catalog ops).

## Scope

- Read-only billing catalog / plan-drift view on the kit.
- Backed by the existing catalog ops + colonel read path (`GetAvailablePlans`); no new mutating endpoints.
- Explicitly **out of scope:** catalog sync / any write — stays CLI-only until this view is trusted.

## Grounding — files & pointers

- Existing ops (read side): `apps/web/billing/operations/catalog/`, `apps/web/billing/operations/materialize_plans.rb`
- Colonel read logic: `apps/api/colonel/logic/colonel/get_available_plans.rb`
- Ops contract: `lib/onetime/operations/README.md`
- Routes: `apps/api/colonel/routes.txt`
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `StatCard`, `JsonViewer`, `FilterBar`
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Read-only catalog/drift view renders on the kit over the existing read ops / `GetAvailablePlans`.
- [ ] Drift between configured catalog and live plans is visible (e.g. side-by-side or diff via `JsonViewer`).
- [ ] No mutating routes or sync actions added — read-only.
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Keep it strictly read-only; adding sync later is a separate, trust-gated PR.
- Drift presentation should make "config says X, Stripe/live says Y" obvious at a glance — that's the whole value.
