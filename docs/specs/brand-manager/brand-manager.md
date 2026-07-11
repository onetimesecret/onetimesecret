# Brand Manager — expanded token vocabulary (design spec)

Status: **shipped, superseding this doc's original design**. The token
vocabulary and backend (§1–§2) landed as designed in PR #3671 (issue #3646).
The editor UI then went through a **second rebuild** — commit `b09e7086f`,
"Rebuild Brand Manager as three-path editor" (#3694) — which replaced the
single `BrandSettingsBar` control row this doc originally specified with a
Simple / Match / Advanced path switcher. This revision documents what's
actually in the branch today: what's done, what changed from the original
design, and what's still open.

> Placed under `docs/specs/` (repo convention) rather than the requested
> `docs/spec/`, and named kebab-case to match the sibling specs.

## TL;DR

- The schema/backend vocabulary described below is fully implemented and
  validated — nothing changed there since the original design.
- The **editor UI is narrower than originally specified**. Only 3 of the ~9
  planned controls are exposed: `primary_color`, corners (3 of 6
  `border_radius` presets), and `font_family`. `secondary_color`,
  `background_color`, `text_color`, and `heading_font` are all built
  end-to-end (schema → validation → runtime CSS injection) but have **no UI
  control anywhere** — not deferred-with-a-placeholder, just absent.
- The 10 built-in **theme presets are a separate case: deliberately not
  surfaced.** A curated-theme gallery models individual aesthetic preference;
  this feature exists to match an operator's *existing* brand (the Match path).
  `brandPresets` is therefore abandoned-direction dead code, not a gap (§3).
- The editor is now a **three-path switcher** (Simple / Match my site /
  Advanced) — a structure this doc's original version didn't anticipate.
  Only Simple is functional; the other two are static, non-interactive
  "coming soon" mockups.
- Everything remains a **closed allowlist** — no custom CSS, no free-form
  fonts, no arbitrary values, on every path including Advanced. This is a
  deliberate security (XSS) boundary and did not change in the rebuild.
- The feature is still gated behind the `custom_branding` entitlement.

## 1. Token inventory & allowed values

All tokens live in the per-domain `BrandSettings` schema (unchanged since
original design). Colors are hex only, normalized to 6-digit uppercase on
save. The **UI control** column is new in this revision — it's now a
materially different question from "renders today," since three tokens have
neither.

| Token | UI control (Simple path) | Renders on recipient page? | Allowed values |
|---|---|---|---|
| `primary_color` | ✅ ColorPicker | ✅ yes | any hex |
| `secondary_color` | ❌ none | ❌ no (CSS var live, no consumer — §4) | any hex |
| `background_color` | ❌ none | ❌ no (CSS var live, no consumer — §4) | any hex |
| `text_color` | ❌ none | ❌ no (CSS var live, no consumer — §4) | any hex |
| `font_family` (body) | ✅ native `<select>`, full 8-value vocabulary | ✅ yes | 8 curated fonts (below) |
| `heading_font` | ❌ none | ❌ no (falls back to `font_family`) | 8 curated fonts; falls back to body font when unset |
| `border_radius` | ⚠️ 3 hand-rolled buttons (`none`/`md`/`full` only) | ✅ yes | preset keyword **or** integer px `0–64` |
| `corner_style` (legacy) | ❌ removed from UI (as recommended — §5) | ✅ yes, only if `border_radius` unset | `rounded` / `square` / `pill` |
| `button_text_light` | ❌ none | ✅ yes (existing behavior, unchanged) | boolean |
| theme preset | ❌ none — out of scope by decision; `brandPresets` is dead code (§3) | n/a | one of 10 |

### Curated fonts (`font_family` and `heading_font`)

Unchanged — closed allowlist of 8, all still valid and implemented backend +
schema side:

| Value | Label |
|---|---|
| `sans` | Sans Serif |
| `serif` | Serif |
| `mono` | Monospace |
| `system` | System UI |
| `slab` | Slab Serif |
| `rounded` | Rounded |
| `humanist` | Humanist |
| `geometric` | Geometric |

Each maps to a fixed CSS font-family stack (system stacks + self-hosted Zilla
Slab for `slab`). No web-font upload, no free-form family names. The Simple
path's font `<select>` exposes all 8 for `font_family`; there is no
`heading_font` control anywhere.

### Border radius (`border_radius`)

Schema/backend unchanged — accepts **either** a named preset **or** a whole
number of pixels `0–64`:

| Value | Label | Rendered |
|---|---|---|
| `none` | Square | `0px` |
| `sm` | Slightly Rounded | `0.25rem` |
| `md` | Rounded | `0.5rem` (default) |
| `lg` | Very Rounded | `0.75rem` |
| `xl` | Extra Rounded | `1rem` |
| `full` | Pill | `9999px` |

**UI regression from the original design intent**: the Simple path exposes
only 3 of these 6 presets (Square/`none`, Rounded/`md`, Pill/`full`) as
fixed buttons — `sm`/`lg`/`xl` and the numeric-px escape hatch this doc
called for are schema-only, unreachable from any control
(`SimpleBrandPanel.vue`). This re-imposes close to the old 3-value
`corner_style` ceiling the expanded token was meant to lift. No numeric
input or 6-way selector exists yet on any path.

## 2. Validation & inline feedback

Backend validation is unchanged and fully implemented
(`brand_settings.rb`, `validate!`):

- **`primary_color`** — format-only (hex regex). WCAG contrast is **not**
  enforced on save (product decision 2026-07;
  `validate_extra_color_fields!` comment, `brand_settings.rb:242`).
- **`secondary_color` / `background_color` / `text_color`** — format-only
  hex validation, same rule, no contrast gate on any of them.
- **`heading_font`, `border_radius`, `corner_style`** — enum/range
  validated, no contrast dimension applies.

In-editor advisory feedback (UI side) is narrower than originally specified:

- **`primary_color` vs. white** — implemented (`SimpleBrandPanel.vue:76-77`,
  key `web.branding.low_contrast_warning`). Advisory only, never blocks
  save. Note: the underlying check (`checkBrandContrast`) reports
  `max(vs-white, vs-black)` — the auto-picked button-text contrast — whose
  minimum across all hues is ≈4.58, just above the 4.5 AA threshold. The
  warning is effectively dormant today; it's kept as a safety net in case
  the threshold tightens.
- **`text_color` vs. `background_color`** — **has no home**. Neither field
  has a UI control, so the advisory pill this doc originally specified was
  never built. The locale key for it (`low_contrast_text_bg_warning`) exists
  in `workspace-branding.json` with zero call-sites — dead copy.

## 3. Theme presets — implemented, but a superseded direction

The 10 presets described in the original design are fully implemented in
`src/shared/utils/brand-helpers.ts` (`brandPresets`, from a `// Theme
presets (#3646)` marker) with the same token values as this table:

| Preset | Primary | Secondary | Background | Text | Body / Heading font | Radius |
|---|---|---|---|---|---|---|
| Midnight | `#4F46E5` | `#0EA5E9` | `#0F172A` | `#E2E8F0` | Sans / Geometric | md |
| Forest | `#047857` | `#65A30D` | `#F7FBF9` | `#14261E` | Humanist / Slab | lg |
| Sunset | `#DB2777` | `#F97316` | `#FFF7F9` | `#2B1220` | Rounded / Rounded | xl |
| Slate | `#334155` | `#0891B2` | `#FFFFFF` | `#1E293B` | System / System | sm |
| Royal | `#6D28D9` | `#DB2777` | `#FBF9FF` | `#241633` | Serif / Slab | md |
| Terminal | `#15803D` | `#4ADE80` | `#0B0F0C` | `#D1FAE5` | Mono / Mono | none |
| Coral | `#E11D48` | `#F59E0B` | `#FFFBF7` | `#2A1512` | Sans / Humanist | lg |
| Ocean | `#0369A1` | `#0D9488` | `#F5FBFF` | `#0C2231` | Geometric / Geometric | md |
| High Contrast | `#000000` | `#1D4ED8` | `#FFFFFF` | `#000000` | System / System | sm |
| High Contrast Dark | `#2563EB` | `#FDE047` | `#000000` | `#FFFFFF` | System / System | sm |

**Status: dead code — and a deliberately abandoned direction, not a gap.**
`brandPresets` has exactly one non-test reference — its own definition. No
component imports or renders it; there is no preset gallery, swatch row, or
picker anywhere in the three-path editor. This is **not** the "highest-value
zero-effort path" the original doc flagged, because the product goal changed:
brand customization exists to **match an operator's existing brand** — that's
what the Match-my-site path is for — **not** to offer a gallery of individual
theme preferences (Midnight, Forest, Sunset…). A curated-theme picker is the
wrong model for that goal. `brandPresets` and its `theme_presets` locale key
are therefore dead code to **remove** (§9), not a surface to build.

## 4. What renders today vs. what's wired-but-unconsumed

This is more nuanced than the original two-state framing ("renders" /
"doesn't render yet"). The rebuild's `useBrandTheme.ts` wires the full
expanded vocabulary onto `<html>` as CSS custom properties — the pipe is
built schema → validate → store → inject; only the last mile (a branded view
actually using the variable) is missing:

- **Renders now**, editor + recipient page alike: `primary_color`,
  `border_radius`, `font_family`, `button_text_light`.
- **Live on `<html>` as a CSS variable, zero consuming views, no UI
  control**: `secondary_color` → `--color-brand2-*` (11-shade scale),
  `background_color` → `--color-brandbg`, `text_color` → `--color-brandtext`.
  Activating any of these needs no JS — just a utility class
  (`bg-brand2-500`, `bg-brandbg`, `text-brandtext`) on a `branded/*` view —
  but nothing does that yet, and there's also no way for a user to set them.
- **Computed and ready, zero consuming views, no UI control**:
  `heading_font` → `identityStore.headingFontClass`
  (`identityStore.ts:319`), not applied to any `<h1>`–`<h3>` yet.
- **Known gotcha for whoever wires the recipient views**: the workspace
  editor's own preview (`SecretPreview.vue`) reads `domainBranding` inline,
  not the `<html>` CSS variables `useBrandTheme` sets — wiring a live branded
  view does not automatically wire the editor preview to match, and
  vice versa.

**The decision this doc asked engineering to confirm** ("flag these as
coming soon" vs. "sequence the rollout") was resolved by neither option —
the rebuild chose a third path: drop the controls from the UI entirely.
Defensible (a control with no visible effect is worse than no control), but
it was a silent resolution of a decision this doc explicitly flagged as
needing sign-off, not an assumption.

## 5. `corner_style` vs `border_radius` — resolved as recommended

This doc's recommendation shipped exactly as written: `corner_style` was
**dropped from the UI**, `border_radius` is what the Simple path's corner
buttons write, and precedence is `border_radius` first, `corner_style`
fallback — both in the operator's own theme (`identityStore.ts:300-306`,
`cornerClass`) and in the recipient preview (`SecretPreview.vue`,
`cornerClass` computed). `corner_style` remains schema-only for back-compat,
as specified. No further action needed here.

## 6. Preview behavior

Unchanged in substance, moved in code. The live preview is now
`BrandPreviewColumn.vue` (not `BrowserPreviewFrame.vue`, which this doc
originally named and which the rebuild orphaned — see §9). It's a fixed
right-hand column, wraps `SecretPreview` in a visually distinct "stage"
(tinted background + persistent "Preview" tag) rather than a browser-chrome
frame, and still reads the **edited domain's** settings directly, not the
operator's own injected theme. It reflects `primary_color`, `border_radius`,
and `font_family` only — same three tokens as the recipient page, per §4.
`BrandPreviewColumn.vue` explicitly does not render a `secondary_color`
accent, by design, so the preview doesn't imply a capability that doesn't
exist yet.

## 7. Hard constraints (unchanged, still hold)

- **Closed vocabulary only** — no custom CSS, no free-form fonts, no
  arbitrary token maps. Everything is allowlisted (security/XSS boundary).
  Verified intact through the rebuild: the Advanced path's `@theme`-style
  mockup (`BrandAdvancedTeaser.vue`) is static markup with no real inputs.
- **Colors are hex only**, normalized to 6-digit uppercase.
- **Entitlement-gated** behind `custom_branding` — the locked/upsell state
  (`DomainBrand.vue`, amber upgrade banner) is implemented.
- The editor is fully controlled: every control emits the whole updated
  `BrandSettings` object; there's no per-field persistence subtlety.
- **New surface to plan for**: the Match path's mockup
  (`BrandMatchTeaser.vue`) illustrates reading brand colors from an
  arbitrary external URL ("Read brand from https://example.com"). It's
  currently 100% static/decorative — no fetch happens. If this path is ever
  built for real, fetching and parsing an operator-supplied URL is a new
  SSRF/untrusted-content surface this doc's original constraints didn't
  anticipate; scope it before implementation, not after.

## 8. New in this rebuild (not covered by the original design)

None of this was anticipated when this doc was written; it's the substance
of commit `b09e7086f`:

- **Three-path editor** (`BrandPathSwitcher.vue` + `paths.ts`): Simple /
  Match my site / Advanced. Only Simple (`available: true` in
  `BRAND_PATHS`) is functional. Switching paths never mutates
  `brandSettings` — confirmed by test
  (`BrandEditor.spec.ts`: "switching paths never mutates brandSettings").
  Match and Advanced render static, hardcoded-English, non-interactive
  mockups (`BrandMatchTeaser.vue`, `BrandAdvancedTeaser.vue`) inside a
  generic dimmed/blurred wrapper (`ComingSoonPanel.vue`).
- **Brand | Delivery tabs** on `DomainBrand.vue`: a new "Delivery" tab
  (`DeliveryPanel.vue`) holds per-domain language and reveal-instructions
  (before/after text, 500-char max), moved out of the brand editor. Both
  tabs edit the same shared `BrandSettings` record; a single header Save
  persists either. No live preview on the Delivery tab, by design — the
  Brand tab's preview is considered the shared preview surface.
- **`DomainHeader.vue` opt-in props**: generic `back-visible`, `save-visible`,
  `save-disabled`, `save-loading`, `@back`, `@save` — all default off, so the
  7 other domain pages sharing this header are unaffected. `DomainBrand.vue`
  is the first consumer, collapsing what used to be a separate back-button
  row and save action bar into the header.

## 9. Where things live (for design↔eng handoff) — updated

The original file map is stale; `BrandSettingsBar.vue` no longer exists.

- Editor entry point: `src/apps/workspace/domains/DomainBrand.vue` (tabs +
  entitlement gate)
- Three-path editor: `src/apps/workspace/components/dashboard/brand/`
  - `BrandEditor.vue` — orchestrates path switch + two-column layout
  - `BrandPathSwitcher.vue`, `paths.ts` — the 3-card switcher
  - `SimpleBrandPanel.vue` — the only functional path (3 controls)
  - `BrandMatchTeaser.vue`, `BrandAdvancedTeaser.vue` — static mockups
  - `ComingSoonPanel.vue` — generic dim/blur/overlay wrapper for teasers
  - `BrandPreviewColumn.vue` — fixed preview column (replaces
    `BrowserPreviewFrame.vue`)
- Delivery tab: `src/apps/workspace/components/dashboard/DeliveryPanel.vue`
- Recipient-page render: `SecretPreview.vue` (same `dashboard/` dir)
- Control primitives: `ColorPicker.vue`
  (`src/shared/components/common/`) — `CycleButton.vue` /
  `CycleButtonText.vue` are **no longer used** anywhere; the corner buttons
  in `SimpleBrandPanel.vue` are hand-rolled instead.
- Token vocabulary, display/label maps, presets, runtime CSS-var injection:
  `src/shared/utils/brand-helpers.ts` (allowlists, `brandPresets`),
  `src/shared/composables/useBrandTheme.ts` (`<html>` CSS var wiring),
  `src/shared/stores/identityStore.ts` (`cornerClass`, `headingFontClass`)
- Contract / allowed values: `src/schemas/contracts/custom-domain/brand-config.ts`
- Backend model / validation: `lib/onetime/models/custom_domain/brand_settings.rb`
- Copy strings: `locales/content/en/workspace-branding.json` (keys under
  `web.branding.*`)
- Tests: `src/tests/components/BrandEditor.spec.ts` (path switcher, Simple
  panel, Delivery panel), `src/tests/shared/utils/brand-helpers.spec.ts`
  (presets, radius/font helpers)

### Orphaned by the rebuild (safe to delete, currently just unused)

- `src/apps/workspace/components/dashboard/BrowserPreviewFrame.vue` — zero
  remaining consumers.
- `src/apps/workspace/components/dashboard/InstructionsModal.vue` — zero
  remaining consumers (reveal instructions moved into `DeliveryPanel.vue`
  as inline fields).
- `detectPlatform()` in `src/utils/index.ts` — was only used to pick the
  Safari/Edge chrome for the old preview frame; zero consumers now.
- `CycleButton.vue` / `CycleButtonText.vue` — zero consumers anywhere in
  `src/`, not just the brand editor.
- Locale keys with copy but no `t()` call-site in `workspace-branding.json`:
  `secondary_color`, `background_color`, `text_color`, `heading_font`,
  `border_radius`, `theme_presets`, `badge_default`,
  `low_contrast_text_bg_warning`, `preview_and_customize`, `more_options`.

## 10. Remaining work / open decisions

- **Theme presets — decided out of scope, not a gap.** Curated theme
  galleries model individual aesthetic preference; this feature exists to
  match an operator's *existing* brand (the Match path). `brandPresets` is
  abandoned-direction dead code — delete it and the `theme_presets` locale
  key (§9), don't surface it.
- **`border_radius` UI is capped at 3 of 6 presets**, no px input. Restore
  `sm`/`lg`/`xl` and the numeric escape hatch, or explicitly decide the
  3-value set is the permanent Simple-path scope and document that (in
  which case the schema's 6-preset + 0–64px range is over-built for what
  the UI will ever send).
- **`secondary_color` / `background_color` / `text_color` / `heading_font`
  have zero UI path.** The CSS wiring exists and is inert. Needs one of:
  build a real consuming view (branded recipient page picking up
  `bg-brandbg`/`text-brandtext`/`bg-brand2-*`/`headingFontClass`) and then
  add the controls back, or formally park the fields and remove the dead
  locale keys/composable branches until there's a view to point them at.
- **Match my site path is 100% mockup.** No fetch, no parsing, no real
  color extraction. Needs a design + security pass (SSRF, untrusted-HTML
  parsing) before any real implementation — see §7.
- **Advanced path is 100% mockup.** Whatever it ends up doing, §7's
  allowlist-only constraint applies without exception, including to any
  copy/export affordance the mockup currently implies ("Copy tokens" /
  "Import .css").
- **Dead code cleanup** (§9 orphan list) — low-risk, no design input needed,
  just needs someone to do it.
