---
labels: admin-v2, work, architecture
depends: none
issue: "#3653"
---

# Colonel Admin Rebuild — operating console (tracking)

## Summary

Rebuild the Colonel admin frontend and finish the Operations-layer extraction so every admin capability is written once and served three ways: an op call, the CLI, and the UI. The backend architecture is already close; the work is a UI rebuild (its own Rolldown-Vite entry, a real UI kit, per-resource stores) plus extracting `Operations::*` so the CLI and admin API become thin adapters over the same verbs.

## Why now

Today the CLI and admin API are parallel implementations, not a shared core. The CLI column is full where the UI column is empty, and the shared Operations layer that would unify them is only partially adopted: `apps/web/auth/operations/` exists and is shared for verify/unverify, but the colonel API bypasses operations entirely and calls models directly. Admin code also ships in the customer bundle today. This epic closes both gaps at once.

## Grounding corrections

So implementers don't follow stale assumptions:

1. **Build tool is Rolldown-Vite.** Single-bundle output is configured via `vite.config.ts:257-282` (`rolldownOptions` / `output.codeSplitting:false`), NOT rollup/`manualChunks`/`inlineDynamicImports`. A second entry means a new rolldown input, not a rollup chunk config.
2. **The HTML shell is a backend Rhales `.rue` template** (`apps/web/core/templates/index.rue`), NOT a static `index.html`. A second shell is a new `.rue` plus a manifest entry.
3. **The incumbent Operations home is app-scoped** `apps/web/auth/operations/` (plus `apps/web/billing/operations/`), NOT a central `lib/onetime/operations/`. Decision D3 should treat app-scoped as the incumbent.

## Decisions (settle before Phase 0)

- **D1 — New dir, same URL.** New frontend lives in `src/apps/admin/`; the URL stays `/colonel` (wired into auth redirects and backend routes). "Colonel" remains the role and product name.
- **D2 — Reuse the core Page controller.** Serve an admin shell template selected by the existing `role=colonel` routes. Do NOT stand up a second web app — resist until CIDR isolation gives a concrete reason.
- **D3 — Ops placement.** Domain-owned ops stay app-scoped (billing, auth, domains). Cross-cutting admin verbs (customers, sessions, queues, banners) go central. Codify the rule in `lib/onetime/operations/README.md`.
- **D4 — Mutation guardrails.** Typed-confirmation dialogs (retype email/ID) for destructive verbs; dry-run default where the op supports it; audit log as the non-negotiable backstop.

## Roadmap & dependency graph

**Phase 0 — Scaffold:**
- [ ] [second Rolldown entry + admin shell served behind experimental.admin_v2](./10-second-entry-shell.md)
- [ ] [admin UI kit (DataTable, StatCard, FilterBar, DetailDrawer, ConfirmDialog, JsonViewer)](./11-admin-ui-kit.md)
- [ ] [per-resource Pinia stores + shared paginated-fetch composable](./12-resource-stores.md)

**Phase 1 — Customers reference slice:**
- [ ] [AdminAuditEvent — every mutating operation records actor/verb/target/result](./21-admin-audit-log.md)
- [ ] [extract Operations::Customers::* and wire colonel + CLI through one implementation](./20-ops-customers-extraction.md)
- [ ] [Customers UI — filterable list + customer detail page (support without SSH)](./22-customers-ui.md)

**Phase 2 — Parity ports:**
- [ ] [Secrets screen (list + receipt + guarded delete)](./30-secrets-screen.md)
- [ ] [Domains screen (card grid + verify button)](./31-domains-screen.md)
- [ ] [Organizations screen + billing-investigate workflow](./32-organizations-screen.md)
- [ ] [System, BannedIPs, Usage screens (+ extract BanIP/UnbanIP ops)](./33-system-bannedips-usage-screens.md)

**Phase 3 — Surface CLI-only powers:**
- [ ] [Sessions console (inspect / search / delete)](./40-sessions-console.md)
- [ ] [Broadcast banner (set / show / clear)](./41-broadcast-banner.md)
- [ ] [Queue DLQ console (list / show / replay / purge)](./42-queue-dlq.md)
- [ ] [Domain toolbox (repair / orphaned-scan / probe / transfer)](./43-domain-toolbox.md)
- [ ] [Email + rate-limit tools (template preview / test send / limiter inspect)](./44-email-ratelimit-tools.md)
- [ ] [Billing catalog view (read-only drift)](./45-billing-catalog-view.md)

**Phase 4 — Cutover & hardening:**
- [ ] [retire old app + tighten perimeter (cutover & hardening)](./50-cutover-hardening.md)
- [ ] [opt-in network isolation middleware (site.admin.allowed_cidrs)](./51-cidr-isolation.md)
- [ ] [explicit, audit-logged impersonation operation (confirm-then-fix)](./52-impersonation-audit-fix.md)

**Backend debt (fix in-flight):**
- [ ] [replace SCAN-counted secret counts with per-customer counters](./60-debt-scan-counts.md)
- [ ] [implement real global stats or drop the stubbed tiles](./61-debt-stats-stubs.md)

Everything depends on Phase 0. In Phase 1 the audit-log (21) precedes the customers op-extraction (20). Phase 2 and 3 screens depend on the kit (11, 12) plus the proven customers slice (22). Cutover (50) waits for Phase-2 parity. The impersonation fix (52) needs the audit log (21).

## Related prior art

- #2081 (closed) — org roles/permissions/audit-logging roadmap; this epic delivers the admin-audit-log slice.
- #2211 (closed) — Colonel API blocking Redis `KEYS`; see the debt issue for the counter fix.
- #2349 (closed) — orgs billing admin view; the Phase-2 organizations port preserves it.
- #2244 (closed) — entitlement override / plan testing mode.
- #3072 (closed) — colonel users-list API key mismatch.
- #3243 (open) — custom-domain route guard; related middleware work.

## Non-goals

- No second backend service, no new API namespace, no auth rework — the two-layer authz is done.
- Extraction PRs preserve CLI behavior bit-for-bit; improvements ship as separate PRs.
- Nothing in Phases 0–3 changes existing endpoint contracts (new endpoints only, for self-hosted compatibility). The Zod schemas are the tripwire.
