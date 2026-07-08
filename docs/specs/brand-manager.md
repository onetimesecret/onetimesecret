# Brand Manager — expanded token vocabulary (design spec)

Status: implemented in PR #3671 (issue #3646). This document is the design
handoff for updating the Brand Manager editor UI to the expanded branding
vocabulary. It describes the tokens, their allowed values, validation rules,
what renders today vs. later, and the layout problems to solve.

> Placed under `docs/specs/` (repo convention) rather than the requested
> `docs/spec/`, and named kebab-case to match the sibling specs.

## TL;DR for the designer

- The editor went from **3 controls → ~9 controls + a preset row**. The
  existing single horizontal bar (`BrandSettingsBar`) no longer scales — the
  primary task is a layout that holds this vocabulary comfortably.
- Everything is a **closed allowlist** — no custom CSS, no free-form fonts, no
  arbitrary values. This is a deliberate security (XSS) boundary; do not design
  a "paste your own CSS" affordance.
- **Four of the new tokens are configurable but do not render yet**
  (`secondary_color`, `background_color`, `text_color`, `heading_font`). Decide
  how to present controls whose visual effect is deferred — see §4.
- The feature is gated behind the `custom_branding` entitlement; design the
  locked/upsell state.

## 1. Token inventory & allowed values

All tokens live in the per-domain `BrandSettings` schema. Colors are hex only,
normalized to 6‑digit uppercase on save.

| Token | Control | Allowed values | Renders today? |
|---|---|---|---|
| `primary_color` | color picker | any hex | ✅ yes |
| `secondary_color` | color picker | any hex | ❌ not yet (§4) |
| `background_color` | color picker | any hex | ❌ not yet (§4) |
| `text_color` | color picker | any hex | ❌ not yet (§4) |
| `font_family` (body) | select/cycle | 8 curated fonts (below) | ✅ yes |
| `heading_font` | select/cycle | 8 curated fonts; falls back to body font when unset | ❌ not yet (§4) |
| `border_radius` | select/cycle or slider | preset keyword **or** integer px `0–64` | ✅ yes |
| `corner_style` (legacy) | select/cycle | `rounded` / `square` / `pill` | ✅ yes (superseded — §5) |
| `button_text_light` | toggle | boolean (light vs. dark button text) | ✅ yes |
| theme preset | swatch/gallery | one of 10 (§6) | applies the above |

### Curated fonts (`font_family` and `heading_font`)

Closed allowlist of 8. Value → display label:

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
Slab for `slab`). No web-font upload, no free-form family names.

### Border radius (`border_radius`)

Accepts **either** a named preset **or** a whole number of pixels `0–64`.
Presets and their rendered sizes:

| Value | Label | Rendered |
|---|---|---|
| `none` | Square | `0px` |
| `sm` | Slightly Rounded | `0.25rem` |
| `md` | Rounded | `0.5rem` (default) |
| `lg` | Very Rounded | `0.75rem` |
| `xl` | Extra Rounded | `1rem` |
| `full` | Pill | `9999px` |

Design choice: presets give the zero-typing path; the numeric px form (0–64) is
the escape hatch that lifts the old 3-value ceiling. A stepped slider with
preset stops is one natural way to present both in one control.

## 2. Validation & inline feedback (must warn before save)

The backend rejects invalid input; the editor must surface these **in-editor**
so users never hit a save error for a normal edit:

- **`primary_color`** — must clear **WCAG AA 3:1 vs white** (it's the main
  button surface). Existing amber contrast pill.
- **`text_color` on `background_color`** — must clear **WCAG AA 4.5:1** (normal
  text) whenever **both** are set. New amber pill added in this PR; only shown
  when both halves are present.
- **`secondary_color`** — format-validated only, **no contrast gate** (it's a
  decorative accent with no fixed text pairing). No warning.

Design need: a clean way to show up to two independent contrast warnings
without clutter. Consider attaching each warning to its relevant control rather
than stacking pills.

## 3. Theme presets

Ten one-click presets. Applying one is a shallow merge of the cosmetic token
subset onto current settings — it **never** touches identity fields (logo,
product name, instructions). The active-preset indicator lights up only when
the current settings fully match a preset's tokens.

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

`High Contrast` / `High Contrast Dark` are accessibility presets (21:1 text
contrast, WCAG AAA). Presets are currently rendered as small circular swatches
with a primary→secondary gradient; a richer **preset gallery** with real
miniature previews is a strong opportunity — presets are the highest-value
zero-effort path.

## 4. ⚠️ What renders today vs. what's deferred (most important caveat)

The rendering pipeline is only partly wired:

- **Renders now** (visible on the recipient's secret page **and** in the editor
  preview): `primary_color`, `border_radius`, `font_family`,
  `button_text_light`.
- **Configurable, validated, and stored — but not rendered anywhere yet**:
  `secondary_color`, `background_color`, `text_color`, `heading_font`. The
  last-mile wiring into the branded recipient views is a separate, deferred
  change.

Implication for design: if these four are given equal prominence, a user will
set them and see **no change** in the page or the preview. Recommended options:
1. Group/flag them as "preview coming soon" until the rendering work lands, or
2. Sequence the UI rollout so these controls appear only once they render.

Please treat this as a decision to confirm with engineering, not an assumption.

## 5. Redundancy to resolve: `corner_style` vs `border_radius`

Both exist. `border_radius` is the richer replacement and **takes precedence
when both are set**; `corner_style` (3 values) is retained only for
back-compat. Recommendation: **drop the `corner_style` control from the UI** and
keep it back-compat-only in the schema. Confirm before removing.

## 6. Preview behavior

The live preview (`SecretPreview` inside a Safari/Edge browser chrome frame,
`BrowserPreviewFrame`) shows the **recipient's** view of the domain being
edited. It reads the edited domain's settings directly (not the operator's own
theme). It currently reflects `primary_color`, `border_radius`, and
`font_family`; like the recipient pages, it does **not** yet reflect
`secondary_color` / `background_color` / `text_color` / `heading_font` (§4).

## 7. Hard constraints (cannot be designed around)

- **Closed vocabulary only** — no custom CSS, no free-form fonts, no arbitrary
  token maps. Everything is allowlisted (security/XSS boundary).
- **Colors are hex only**, normalized to 6-digit uppercase.
- **Entitlement-gated** behind `custom_branding` — design the locked/upsell
  state for domains without it.
- The editor is fully controlled: every control emits the whole updated
  `BrandSettings` object; there's no per-field persistence subtlety to design
  around.

## 8. Where things live (for design↔eng handoff)

- Editor: `src/apps/workspace/components/dashboard/BrandSettingsBar.vue`
- Live preview: `SecretPreview.vue` + `BrowserPreviewFrame.vue` (same dir)
- Control primitives: `ColorPicker.vue`, `CycleButton.vue`
  (`src/shared/components/common/`)
- Token vocabulary, display/label maps, presets:
  `src/shared/utils/brand-helpers.ts`
- Contract / allowed values: `src/schemas/contracts/custom-domain/brand-config.ts`
- Copy strings: `locales/content/en/workspace-branding.json` (keys under
  `web.branding.*`, e.g. `secondary_color`, `background_color`, `text_color`,
  `border_radius`, `heading_font`, `theme_presets`, `low_contrast_warning`,
  `low_contrast_text_bg_warning`)
