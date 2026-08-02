---
labels: admin-v2, phase-3, backend, frontend
depends: 11-admin-ui-kit, 12-resource-stores, 22-customers-ui
epic: "#3653"
---

# Admin rebuild: Email + rate-limit tools (template preview / test send / limiter inspect)

## Context

Part of the **Colonel Admin Rebuild** epic, Phase 3 — the operating-console payoff.

CLI-vs-UI gap this closes: email template preview / test send and rate-limiter inspection live **only on `bin/ots`** (`lib/onetime/cli/email/` and `lib/onetime/cli/ratelimit/`). Diagnosing "did the email render / send" and "is this identifier throttled" needs SSH today.

Recipe (uniform for all Phase-3 items): **extract op → add colonel route (BOTH auth layers) → screen on the UI kit.**

## Scope

- Extract email template-preview / test-send and rate-limiter inspect into operations, preserving CLI behavior bit-for-bit.
- Add colonel routes for each, guarded by BOTH auth layers.
- Email tools screen: pick template → preview rendered output; test-send to an operator-supplied address. Rate-limit panel: inspect a limiter/identifier's current state.
- **Test send** dispatches a real email → confirm before sending; limiter inspect is read-only. Test sends audit-logged (issue 21).

## Grounding — files & pointers

- CLI source of truth: `lib/onetime/cli/email/` and `lib/onetime/cli/email.rb`; `lib/onetime/cli/ratelimit/` and `lib/onetime/cli/ratelimit_command.rb`
- Ops home: `apps/web/auth/operations/`; contract `lib/onetime/operations/README.md`
- Routes: `apps/api/colonel/routes.txt`; base logic `apps/api/colonel/logic/base.rb`
- Auth layers: `role=colonel` at Otto router + `verify_one_of_roles!(colonel: true)` in `raise_concerns`
- New app dir: `src/apps/admin/`
- Kit: `DataTable`, `DetailDrawer`, `JsonViewer`, `ConfirmDialog`, form via `src/shared/components/ui/*`
- Primitives: `closet/*Skeleton.vue`, `icons/OIcon.vue`
- Schemas: `src/schemas/api/account/responses/colonel`
- Axios: `useApi()` — `src/shared/composables/useApi.ts`

## Acceptance criteria

- [ ] Template-preview / test-send / limiter-inspect extracted into operations; existing CLI specs pass unchanged.
- [ ] Colonel routes added with BOTH auth layers.
- [ ] Email tools screen: template preview renders; test-send to a supplied address, gated by confirm.
- [ ] Rate-limit inspect panel shows current limiter state for an identifier (read-only).
- [ ] Test sends recorded in the audit log (issue 21).
- [ ] Zod schemas under `src/schemas/api/account/responses/colonel`.

## Notes / risks

- Test send hits the real mailer — never auto-send on template select; require an explicit address + confirm.
- Preview must render template output without side effects (no real dispatch on preview).
