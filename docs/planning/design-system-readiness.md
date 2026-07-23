# Design System Readiness — Audit & Rolling-Wave Plan

**Date:** 2026-07-23
**Scope:** All four frontend apps (`src/apps/{secret,workspace,session,admin}`), the shared
layer (`src/shared/`), tokens (`src/assets/style.css`), and packaging.
**Planning style:** Rolling wave / progressive elaboration — Wave 1 is specified to
task-level detail; later waves are intentionally coarse and get elaborated as the
preceding wave lands and teaches us more.

---

## 1. Executive summary

The codebase is **not yet ready to extract a design system library**, but the gap is
narrower than it looks:

- **Best-in-class foundation:** the design-token and runtime custom-domain branding
  stack (`@theme static` in `src/assets/style.css`, `useBrandTheme.ts`,
  `brand-palette.ts` with WCAG contrast checking) is production-grade and already
  token-driven. This is the asset to build around.
- **Missing primitive layer:** there is **no shared `Button`, `Input`, `Field`,
  `Card`, `Table`, or generic `Dialog` shell anywhere** in `src/shared/components`.
  Every app hand-rolls these (hundreds of raw `<button>`/`<input>` sites). This one
  gap drives most of the duplication and inconsistency found below.
- **The seed exists:** `src/apps/admin/components/kit/` is a deliberate,
  documented proto-design-system with library-grade typed props/slot APIs.
  `OIcon` is the one primitive that already behaves like a design system
  (universally adopted, ~470 uses in workspace alone).

**Verdict:** build tokens-for-neutrals and the atomic primitives *inside*
`src/shared` first; only then draw a package boundary. Extracting a package today
would ship the duplication as a library.

## 2. Maturity scorecard

### 2.1 Per-app

| App | Overall | Strengths | Weaknesses |
|---|---|---|---|
| `admin` | **3.5/5** | Documented UI kit (`components/kit/`: DataTable, AdminModal, StatCard, FilterBar, KitPagination) with typed generic props, slots, `v-model` contracts; zero hardcoded hex; disciplined shared-component reuse | ~1,650 raw `gray-*` utilities; 96 raw `<button>` / 24 raw `<input>` because no atom exists beneath the kit's molecules; thinner per-surface aria coverage (~38 `aria-*`) |
| `secret` | **2.7/5** | Heaviest brand-token consumer (~122 `brand-*` uses); strong a11y (`aria-live`, `sr-only` status, focus rings); 82% of files have `dark:` coverage | `canonical/` vs `branded/` component forks are copy-and-diverge duplication; 10+ `SecretLinksTableRow*` variants; no variant API — raw `cornerClass` string props (`ConcealButton.vue`) |
| `session` | **2.0/5** | Best a11y craft in the repo (~189 `aria-*` refs; full `aria-invalid`/`describedby` wiring; sr-only announcements); consistent dark mode | Zero abstraction: the same `bg-brand-600` submit-button block appears in 14 files; the ~8-line input class string is duplicated in every form (`SignInForm.vue:101-109`); one hardcoded hex `#d45a2a` bypasses tokens |
| `workspace` | **2.0/5** | Heavy healthy reliance on shared logic (`OIcon` ×469, shared stores/composables ×324 imports); near 1:1 light/dark utility pairing | Worst duplication: 159 raw buttons, 51 raw inputs, 11 hand-rolled tables, 6 feature modals rebuilding dialog chrome; ~5:1 hardcoded-vs-brand color ratio; split folder roots (`billing/` vs `components/billing/`, three `account` locations); focus styles on <50% of interactive files |

### 2.2 Foundation

| Area | Rating | Notes |
|---|---|---|
| Runtime domain branding | **5/5** | `src/shared/composables/useBrandTheme.ts` + `src/utils/brand-palette.ts`: 44-key CSS-var palette injection, memoization, WCAG `contrastRatio()`, clean fallback to compiled `@theme static` defaults; 3-step fallback chain in `src/shared/constants/brand.ts` |
| Design tokens | **4/5** | Tailwind v4 CSS-first (`src/assets/style.css:38` `@theme static`): six 11-shade brand scales (`brand`, `branddim`, `brandcomp`, `brandcompdim`, `brand2`), `--font-brand-*` stacks, `--radius-brand`. **Gap: neutrals are not tokenized** — ~4,000 raw `gray-*`/`slate-*` utilities repo-wide, no semantic `surface`/`ink`/`muted` layer |
| Icon system | **4/5** | `OIcon` sprite system, 9 collections, lazy registry, a11y-conscious. Universally adopted |
| Shared components | **3/5** | 94 components in coherent families (modals on headlessui + focus-trap, split global/inline notification system, skeletons) — but no atoms |
| Docs / Storybook / tests | **2/5** | No Storybook; ~10% component spec coverage; `.interface-design/system.md` has drifted from code (documents flame-orange `#dc4a22` brand vs the neutral-blue default in `brand.ts`) |
| Library packaging | **2/5** | `pnpm-workspace.yaml` has no `packages:` field (no real workspaces); no Vite lib build, no `exports` map; `@/shared/*` alias would need rewiring |

## 3. Key evidence (for future reference)

- Duplicated input class string: `src/apps/session/components/SignInForm.vue:101-109` (and again at `:132-140`) — the canonical template for a future `BaseInput`.
- Library-grade API precedent: `src/apps/admin/components/kit/DataTable.vue:29-65` (generic `<T>`, typed columns, controlled sort, cell/header slots); `AdminModal.vue:30-57` (`v-model:open`, `dismissable`, typed emits).
- Kit intent & isolation: `src/apps/admin/components/kit/index.ts:1-25`.
- Copy-and-diverge fork: `src/apps/secret/components/canonical/SecretDisplayCase.vue` (263 lines) vs `branded/SecretDisplayCase.vue` (195 lines).
- Token system: `src/assets/style.css:31-152` (incl. the documented `@theme static` rationale); extended tokens (`brand2-*`, `brandbg`, `brandtext`, `rounded-brand`) are injected but not yet consumed by any view (`style.css:99-109`).
- Missing atoms: `src/shared/components/ui/` contains only specialized buttons (`CopyButton`, `SplitButton`, `ButtonGroup`) — no generic `Button`/`Input`.

---

## 4. Rolling-wave plan

Waves are sequenced by dependency, not calendar. Each wave ends with a review that
elaborates the next wave to task-level detail and updates this document
(progressive elaboration — later waves below are deliberately coarse).

### Wave 1 — Atoms + neutral tokens (elaborated now, ready to execute)

Goal: create the missing primitive layer inside `src/shared` and the semantic
neutral tokens it needs. No package extraction yet. No mass migration yet —
each primitive is proven in one pilot surface per app.

1. **Semantic neutral tokens** in `src/assets/style.css` `@theme` block:
   `--color-surface-*` (page/raised/sunken), `--color-ink-*` (default/muted/faint),
   `--color-edge-*` (border/divider), mapped to the existing gray ramp with
   light/dark values so `dark:` pairs collapse into the token layer. Follow the
   existing `@theme static` pattern so custom domains can override them later.
2. **`BaseButton`** (`src/shared/components/base/BaseButton.vue`):
   typed `variant` (`primary | secondary | ghost | danger`), `size` (`sm | md | lg`),
   `loading`, `disabled`. Merge session's a11y treatment (sr-only busy status,
   `aria-busy`) with admin-kit's API style. Built-in focus-visible ring —
   this fixes workspace's missing-focus-state gap by construction. Absorb the
   `cornerClass` smell into a `rounded` variant driven by `--radius-brand`.
3. **`BaseInput` + `FormField`** wrapper (label, hint, error, `aria-invalid`/
   `aria-describedby` wiring lifted verbatim from `SignInForm.vue`). Cover
   `input`, `textarea`, `select` via one field contract.
4. **`BaseCard`** and a generic **`Dialog` shell** (extract the overlay/panel
   chrome the 6 workspace feature modals each rebuild; keep
   `ConfirmDialog`/`SimpleModal` as compositions of it).
5. **Pilot adoption, one surface per app** (proof, not migration):
   session `SignInForm`, workspace `DomainSsoConfigForm`, secret
   `ConcealButton`/`GenerateButton`, admin one kit view. Each pilot deletes its
   local copies of the duplicated class strings.
6. **Tests + doc truth:** component specs for each new atom (pattern:
   `src/tests/shared/components/`); reconcile `.interface-design/system.md`
   with the actual code defaults (resolve the flame-orange vs neutral-blue drift)
   and record the decision in its Decisions Log.

Exit criteria: atoms exist with typed variant APIs, pilots merged, zero new raw
`<button>`/`<input>` in touched files, Wave 2 elaborated from pilot learnings.

### Wave 2 — Promote molecules & migrate (coarse; elaborate at end of Wave 1)

- Promote admin `kit/` upward to `src/shared` (drop the `Admin` prefix; move
  console-specific "heavy-rule" defaults into variants). DataTable replaces the
  11 hand-rolled workspace tables and informs a slot-driven replacement for the
  `SecretLinksTableRow*` sprawl.
- Codemod raw `gray-*`/`slate-*` utilities onto the Wave 1 semantic tokens,
  app by app (expected order: session → secret → workspace → admin, smallest
  and cleanest first).
- Migrate remaining raw buttons/inputs onto the atoms; normalize workspace's
  split folder roots (`billing/` vs `components/billing/`, the three `account`
  locations) as files are touched.
- Open questions to resolve during elaboration: codemod tooling choice;
  whether `brand2` neutrals or Tailwind grays back the semantic tokens;
  per-domain overridability of neutrals.

### Wave 3 — Collapse the branded fork (coarse)

- Merge secret's `canonical/` vs `branded/` component pairs into single
  token-driven components using the existing `useBrandTheme` runtime pipeline —
  the infrastructure already supports this; the fork predates it.
- Wire up the injected-but-unused extended tokens (`brand2-*`, `brandbg`,
  `brandtext`, `rounded-brand`) as the fork collapses.

### Wave 4 — Package boundary & tooling (coarse; only after primitives are proven)

- Real pnpm workspaces (`packages:` field), a Vite library build with an
  `exports` map for the extracted `src/shared` design layer; rewire the
  `@/shared/*` alias.
- Storybook (or Histoire) over the atom/molecule set; raise component spec
  coverage from ~10% toward the primitive set being fully covered.
- Decide the library's public name/scope and versioning policy.

---

## 5. Document maintenance

This is a living planning document. At each wave boundary: mark the completed
wave with outcomes and deviations, elaborate the next wave to numbered
task-level detail, and re-check the scorecard numbers in §2 (they are
point-in-time counts from 2026-07-23 and will drift).
