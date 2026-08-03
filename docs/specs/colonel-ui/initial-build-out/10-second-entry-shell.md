---
labels: admin-v2, phase-0, frontend, backend
depends: none
epic: "#3653"
---

# Admin rebuild: second Rolldown entry + admin shell served behind experimental.admin_v2

## Context
Part of the Colonel Admin Rebuild epic. Phase-0 scaffold: stand up an isolated admin bundle and shell so admin code stops shipping in the customer bundle and future phases have a home. No user-visible change; rollback is a config flip.

## Scope
- Add a **second Rolldown input** `src/admin.ts` alongside `src/main.ts` in the single-bundle config. Each entry stays one chunk (preserves the one-script-tag = one-nonce CSP model).
- Add a new admin shell **Rhales `.rue` template** (sibling to `apps/web/core/templates/index.rue`) that injects the admin entry's assets + per-request nonce.
- Teach the vite_manifest helper to resolve the **second manifest entry** (`admin.ts`), not just the hardcoded `main.ts`.
- Serve the admin shell from the existing `GET /colonel` + `GET /colonel/*` routes via the **core Page controller** (decision D2 — reuse `Core::Controllers::Page#index`, do NOT stand up a second web app), gated on config flag `experimental.admin_v2`. Flag off → existing colonel app renders unchanged.
- Create new app dir `src/apps/admin/` with a **persistent-sidebar layout** (today's colonel nav is quick-actions-only; a console needs a navigable map).

## Grounding — files & pointers
- Vite single-bundle config: `vite.config.ts:257-282` — `rolldownOptions.input { main: 'src/main.ts' }`, `output.codeSplitting: false`, `preserveModules: false`, `cssCodeSplit: false`. CSP-nonce rationale at `vite.config.ts:73-84` and `249-255`.
  - ⚠️ Use a **new rolldown input + its own manifest lookup**. Do NOT reach for `rollupOptions`/`manualChunks`/`inlineDynamicImports` — stale names, not what this repo uses (it is Rolldown-Vite, not Rollup).
- HTML shell: `apps/web/core/templates/index.rue` (there is NO static index.html). Assets via `{{{vite_assets_html}}}`, helper `apps/web/core/views/helpers/vite_manifest.rb` (hardcoded to `main.ts` today), nonce `{{app.nonce}}` minted at `apps/web/core/middleware/request_setup.rb:36`. Head partials: `apps/web/core/templates/partials/head.rue`, `head-base.rue`.
- Routes: `apps/web/core/routes.txt:88-90` — `GET /colonel` + `GET /colonel/*` → `Core::Controllers::Page#index auth=sessionauth role=colonel`. Apps mounted via `config.ru:60` → `Registry.generate_rack_url_map`. Colonel redirect: `apps/web/core/controllers/authentication.rb:113-120`.
- New frontend app dir: `src/apps/admin/` (decision D1; URL stays `/colonel`). Existing colonel SPA `src/apps/colonel/` is untouched.

## Acceptance criteria
- [ ] `src/admin.ts` builds as its own single chunk; manifest emits a distinct admin entry.
- [ ] vite_manifest helper resolves both `main.ts` and `admin.ts` entries.
- [ ] Admin shell `.rue` template injects the admin entry + a valid per-request CSP nonce (one script tag).
- [ ] Flag `experimental.admin_v2` **on** → empty admin shell with persistent sidebar renders at `/colonel`; **off** → legacy `src/apps/colonel/` app renders exactly as before.
- [ ] Customer bundle (`main.ts` output) no longer contains admin code (verify chunk contents).
- [ ] Rollback is a config-flag change only — no code revert required.

## Notes / risks
- CSP invariant is load-bearing: every entry must remain a single chunk; no dynamic import splitting.
- Reuse the core Page controller; resist standing up a second Rack app (D2).
- Phase-0 exit gate lives here: flag on → shell renders; flag off → old app + no admin code in customer bundle.
