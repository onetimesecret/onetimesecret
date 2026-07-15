---
labels: email-quality, phase-1, backend, frontend
depends: 21-suppression-ops-and-cli
epic: TBD
---

# Email quality: colonel suppression endpoints + admin UI

## Context

Part of the **Email Quality Controls** epic, Phase 1. The admin-surface half of
the suppression slice: colonel routes and a Vue screen over the SAME ops slice
21 shipped. Recipe (uniform since #3653 Phase 3): **op → colonel route (BOTH
auth layers) → screen on the UI kit.**

## Scope

- Colonel routes in `apps/api/colonel/routes.txt` (all
  `response=json auth=sessionauth role=colonel scope=internal`; literal routes
  before param routes):
  - `GET  /email/suppressions` → `ListSuppressions` (paginated; reason filter)
  - `GET  /email/suppressions/check` → `CheckSuppression` (operator enters an
    address; server hashes; response includes obscured form + entry + per-
    category effect)
  - `POST /email/suppressions` → `AddSuppression`
  - `DELETE /email/suppressions/:email_hash` → `RemoveSuppression` — refuses
    complaint entries (Q6: complaint removal stays CLI-only; the UI renders the
    refusal reason)
  - `GET  /email/suppressions/:email_hash/events` → `GetEmailActivity`
- Logic classes in `apps/api/colonel/logic/colonel/`: thin adapters —
  `process_params` strips/validates, `raise_concerns` calls
  `verify_one_of_roles!(colonel: true)` (layer 2 of the invariant), `process`
  invokes the op with `actor: cust.extid`, `success_data` returns the
  `{record:, details:}` envelope.
- Admin UI (`src/apps/admin/`): `AdminEmailSuppressions.vue` — DataTable list
  (obscured address, reason badge, scope, source, created, expiry), FilterBar
  by reason, check-an-address form, add form, DetailDrawer with the activity
  timeline, remove gated by `AdminConfirmDialog` typed confirmation +
  `useAdminMutation` (CONTRACT 3). Route in `src/apps/admin/routes.ts`
  (spread `adminDefaultMeta`), sidebar row in
  `src/apps/admin/sections.ts` (`/colonel/email-suppressions`).
- Zod: response schemas in `src/schemas/api/account/responses/colonel*` with
  internal re-exports (the colonel-emailtools pattern); model shape for
  `EmailSuppression.safe_dump` under `src/schemas/shapes/`; locales file
  `locales/content/en/admin-emailsuppressions.json` (`web.admin.…` keys, en
  first — i18n fallbacks cover the rest).

## Grounding — files & pointers

- Route grammar + neighbors: `apps/api/colonel/routes.txt` (existing `/email/*` and `/ratelimit/*` lines; `/banned-ips` is the closest CRUD family)
- Logic adapter templates: `apps/api/colonel/logic/colonel/{ban_ip,send_test_email,reset_rate_limit}.rb`; base `apps/api/colonel/logic/base.rb`
- Two-layer authz invariant: `role=colonel` at the Otto router AND `verify_one_of_roles!(colonel: true)` in every `raise_concerns` (`lib/onetime/application/authorization_policies.rb`) — BFLA tryouts assert both (Slice-6 precedent)
- UI screen template: `src/apps/admin/views/AdminEmailTools.vue` (useApi + gracefulParse + useAdminMutation); BannedIPs screen for the CRUD shape
- Kit: DataTable, FilterBar, DetailDrawer, ConfirmDialog, JsonViewer; composables `useResourceFetch`/`usePaginatedFetch`/`useAdminMutation`
- Schemas precedent: `src/schemas/api/account/responses/colonel-emailtools.ts` (+ internal wrapper)
- Sidebar/localization: `src/apps/admin/sections.ts`, `locales/content/en/admin-emailtools.json`

## Acceptance criteria

- [ ] All routes carry BOTH auth layers; BFLA tryout coverage matches the
      Slice-6 pattern (staff/customer roles get 403/404, colonel passes).
- [ ] Check form: operator pastes an address, sees suppression state + per-
      category effect; the plaintext address is sent over the authenticated
      colonel API only, hashed server-side, and never persisted or echoed into
      the audit log (obscured form only).
- [ ] Add/Remove render op Result statuses faithfully (`:already_suppressed`,
      `:not_suppressed`, complaint-refusal) — no client-side re-derivation.
- [ ] Remove requires typed confirmation (retype the obscured address) and
      surfaces the audit actor convention (`cust.extid` server-side).
- [ ] Zod schemas parse every response; `gracefulParse` degradation leaves the
      screen usable on partial failure.
- [ ] List is paginated server-side (MAX 100/page) — no unbounded fetch
      (CONTRACT 6).

## Notes / risks

- The suppression list is a PII-adjacent surface: obscured forms everywhere,
  no export button in v1 (an export is a mass-PII egress path; `/usage/export`
  precedent can be weighed later with legal review noted in the PR).
- `DELETE` with an email_hash path param is fine under the piiQueryGuard policy
  (hashes are opaque); never put a plaintext address in a URL — the check form
  must POST.
- Screen ships behind nothing: colonel-only surfaces don't need a feature flag
  (the Q2 kill-switch governs enforcement, not visibility).
