---
labels: admin-v2, phase-2, frontend, backend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: System, BannedIPs, Usage screens (+ extract BanIP/UnbanIP ops)

## Context

Part of the **Colonel Admin Rebuild** epic. Phase 2 parity port covering the remaining system screens; one PR. This is the Phase-2 sweep that also does the epic's cleanup and one backend extraction.

CLI-vs-UI gap this closes: `BanIP`/`UnbanIP` are API-only today — the colonel logic calls `Onetime::BannedIP.ban!` directly, with **no operation and no CLI**, so an incident responder on a shell can't ban an IP. While porting the BannedIPs screen, extract ban/unban into operations so incidents can be handled from a shell too.

## Scope

- Straight ports of System (`ColonelSystem.vue`, `ColonelSystemMainDB.vue`, `ColonelSystemRedis.vue`) and Usage export (`ColonelUsageExport.vue`) onto the kit + stores.
- Port BannedIPs (`ColonelBannedIPs.vue`) — replace the hand-rolled add-IP form with kit components.
- **Backend:** extract `BanIP`/`UnbanIP` into operations under `apps/web/.../operations/` (preserve current model-call behavior bit-for-bit); colonel logic classes then call the ops. Keep both auth layers on the mutating routes.
- **Cleanup:** delete the AuthDB stub (`ColonelSystemAuthDB.vue`, 25-line "Coming Soon") and orphaned components `FeedbackSection.vue`, `ColonelNavigation.vue`.

## Grounding — files & pointers

- Views to port: `src/apps/colonel/views/ColonelSystem.vue`, `ColonelSystemMainDB.vue`, `ColonelSystemRedis.vue`, `ColonelUsageExport.vue`, `ColonelBannedIPs.vue` (291 lines)
- Delete: `src/apps/colonel/views/ColonelSystemAuthDB.vue`, `FeedbackSection.vue`, `ColonelNavigation.vue`
- Backend read: `apps/api/colonel/logic/colonel/get_database_metrics.rb`, `get_redis_metrics.rb`, `get_queue_metrics.rb`, `get_system_settings.rb`, `export_usage.rb`, `list_banned_ips.rb`
- Backend mutate to extract: `apps/api/colonel/logic/colonel/ban_ip.rb`, `unban_ip.rb` (currently call `Onetime::BannedIP.ban!` directly)
- Ops home: `apps/web/billing/operations/` / `apps/web/auth/operations/` (app-scoped); contract `lib/onetime/operations/README.md`
- Auth layers: `role=colonel` at the Otto router (`apps/api/colonel/routes.txt`) + `verify_one_of_roles!(colonel: true)` in `raise_concerns` (base `apps/api/colonel/logic/base.rb`)
- Kit: `DataTable`, `StatCard`, `FilterBar`, `ConfirmDialog`, `JsonViewer`
- Primitives: `src/shared/components/ui/*`, `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`

## Acceptance criteria

- [ ] System DB / Redis / metrics screens ported onto `StatCard` / kit + stores.
- [ ] Usage export screen ported (`ExportUsage`).
- [ ] BannedIPs screen ported; add-IP form uses kit components; ban is gated by `ConfirmDialog`.
- [ ] `BanIP`/`UnbanIP` extracted into operations (single `#call`, stateless, returns symbols/immutable `Data`); behavior identical to prior direct model calls.
- [ ] Both auth layers present on ban/unban routes (router `role=colonel` + `verify_one_of_roles!`).
- [ ] AuthDB stub + orphaned `FeedbackSection.vue` / `ColonelNavigation.vue` deleted.
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- `GetColonelStats` fields (secrets_created / secrets_shared / emails_sent) are stubbed at 0 — surface as-is, don't fabricate numbers; wiring real stats is out of scope.
- Op extraction must preserve CLI/behavioral parity bit-for-bit; improvements are a separate PR.
- Phase-2 EXIT gate: with these merged, feature parity with the old colonel app is reached — flag flips default-on for cloud, old app kept one release as fallback.
