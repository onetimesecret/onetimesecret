---
labels: admin-v2, phase-0, frontend
depends: 10-second-entry-shell
epic: "#3653"
---

# Admin rebuild: per-resource Pinia stores + shared paginated-fetch composable

## Context
Part of the Colonel Admin Rebuild epic. Phase-0: replace the single 550-line god-store with one Pinia store per resource, so each admin view owns its state and later phases add resources without touching a shared file.

## Scope
- One Pinia store **per resource** — `useAdminCustomers`, `useAdminSecrets`, … — replacing the monolithic `src/shared/stores/colonelInfoStore.ts` (550 lines holding every resource).
- A **shared paginated-fetch composable** consumed by every resource store (loading/error/page state, cursor/offset handling) — the client-side complement to the index-backed pagination fixed server-side in #20.
- Reuse the existing API + validation stack **unchanged**: Axios `createApi()` at `src/api/index.ts`, the `useApi()` composable at `src/shared/composables/useApi.ts`, and Zod `gracefulParse` from `src/schemas/api/account/responses/colonel`.

## Grounding — files & pointers
- God-store to decompose: `src/shared/stores/colonelInfoStore.ts` (ONE 550-line store holding every resource).
- API layer (do not change): `src/api/index.ts` (`createApi()`), `src/shared/composables/useApi.ts` (`useApi()`), Zod schemas + `gracefulParse` under `src/schemas/api/account/responses/colonel`.
- Stores live under the new `src/apps/admin/` tree (from #10).
- Colonel API these stores call: separately-mounted Otto app at `/api/colonel`, routes `apps/api/colonel/routes.txt` (scope=internal, auth=sessionauth role=colonel).

## Acceptance criteria
- [ ] At least `useAdminCustomers` and `useAdminSecrets` stores exist, each owning only its resource.
- [ ] Shared paginated-fetch composable handles loading/error/page state and is used by each resource store.
- [ ] Existing Zod schemas + `gracefulParse` reused with no schema changes.
- [ ] `useApi()` / `createApi()` reused unchanged (no new HTTP client).
- [ ] No new coupling to `colonelInfoStore.ts`; new admin views depend only on per-resource stores.

## Notes / risks
- Keep the fetch composable server-pagination-friendly so it maps cleanly onto #20's `ZRANGE` index-backed endpoints (avoid re-introducing load-all-then-slice on the client).
- Legacy `colonelInfoStore.ts` stays in place for the untouched legacy colonel app until it is retired.
