---
labels: admin-v2, refactoring
depends: 30-secrets-screen, 31-domains-screen, 32-organizations-screen, 33-system-bannedips-usage-screens
epic: "#3653"
---

# Admin rebuild: retire old app + tighten perimeter (cutover & hardening)

## Context

Part of the Colonel Admin Rebuild epic (Phase 4). Once the Phase-2 screens reach parity, the old admin frontend and its transitional scaffolding become dead weight and a second implementation of every capability. This issue retires them and locks in the security posture so there is one admin frontend, one implementation per capability, and an audit trail.

## Scope

- Delete `src/apps/colonel/` (12 views), the monolithic store `src/shared/stores/colonelInfoStore.ts` (550 lines), and the `experimental.admin_v2` config flag. `src/apps/admin/` becomes the only colonel frontend.
- Add pentest scope: `/api/colonel/*` explicitly included; BFLA checks (a standard-user token fired at every admin route → expect 403/404) added to the security tryouts.
- Write the self-hosted admin guide: promoting a colonel, what the console can do, and how to enable CIDR isolation.
- The CIDR middleware itself is issue 51 and the impersonation fix is issue 52 — reference them here, do not duplicate.

## Grounding — files & pointers

- Old app to delete: `src/apps/colonel/`
- Monolithic store to delete: `src/shared/stores/colonelInfoStore.ts`
- New app (the survivor): `src/apps/admin/`
- Config flag to remove: `experimental.admin_v2`
- Colonel API surface in pentest scope: `/api/colonel`, routes `apps/api/colonel/routes.txt`, handlers `apps/api/colonel/logic/colonel/*.rb`
- Two-layer authz invariant (BFLA cases assert both hold): `role=colonel` at the Otto router in `apps/api/colonel/routes.txt` (scope=internal) PLUS `verify_one_of_roles!(colonel:true)` in each logic class's `raise_concerns`; `cust.verified?` required for any system role.
- SPA shell routes: `apps/web/core/routes.txt:88-90` (`GET /colonel`, `/colonel/*` → `Core::Controllers::Page#index`)

## Acceptance criteria

- [ ] `src/apps/colonel/` and `src/shared/stores/colonelInfoStore.ts` are deleted; no imports remain.
- [ ] `experimental.admin_v2` flag removed from config and all references.
- [ ] `src/apps/admin/` is the only colonel frontend; `/colonel` serves it unconditionally.
- [ ] BFLA tryouts: a standard-user token against every `/api/colonel/*` route returns 403/404; both authz layers are asserted present.
- [ ] `/api/colonel/*` is explicitly enumerated in the pentest scope doc.
- [ ] Self-hosted admin guide published: colonel promotion, console capabilities, enabling CIDR isolation.
- [ ] Outcome holds: one admin frontend, one implementation per capability, an audit trail, config-selectable isolation posture.

## Notes / risks

- Do not cut over until Phase-2 parity is confirmed — deletion is irreversible for the old views.
- Colonel promotion stays CLI-only (`bin/ots customers role promote`); the UI never grants roles to itself.
- The admin bundle must no longer ship to customer/end-user frontends after cutover — verify the bundle split.
