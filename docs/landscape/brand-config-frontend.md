# Frontend Insights from Brand Config Landscape Survey

## 1. CSS / Tailwind Patterns

What the survey reveals:

Both Rallly and Zitadel converge on CSS custom properties as the bridging mechanism between stored brand config and rendered UI. The scale differs sharply:

- Rallly: 4 CSS vars (`--primary-light`, `--primary-light-foreground`, `--primary-dark`, `--primary-dark-foreground`). Consumed by Tailwind via a shared stylesheet:

```css
:root {
  --primary: var(--primary-light, var(--color-indigo-600));
}
```

. Clean, minimal, easy to reason about.

- Zitadel: 44+ CSS vars (11 shades x 4 color axes). Generated once on activation into a static CSS file. A `<link>` element loads it with `?v=` cache-busting.

OTS comparison: OTS generates 44 CSS vars (matching Zitadel's scale), but applies them via `document.documentElement.style.setProperty()` in JavaScript at runtime. This is
the most fragile of the three approaches:

```
┌─────────┬─────────────────────────────────┬─────────────────────────────┬──────────────────┐
│ Project │            Mechanism            │         Generation          │     Delivery     │
├─────────┼─────────────────────────────────┼─────────────────────────────┼──────────────────┤
│ Rallly  │ :root CSS vars in layout render │ Per-request (SSR)           │ Inline on <html> │
├─────────┼─────────────────────────────────┼─────────────────────────────┼──────────────────┤
│ Zitadel │ Static .css file                │ Once on activation          │ <link> element   │
├─────────┼─────────────────────────────────┼─────────────────────────────┼──────────────────┤
│ OTS     │ style.setProperty() in JS       │ Per page load (client-side) │ JS runtime       │
└─────────┴─────────────────────────────────┴─────────────────────────────┴──────────────────┘
```

Key insight: Rallly's fallback pattern is worth studying. Their Tailwind config references `var(--primary-light, var(--color-indigo-600))` -- the second argument to `var()` provides the default. OTS's `@theme` block in `style.css` fills a similar role (the compiled Tailwind defaults are the fallback when no JS override is present), but the mechanism is implicit rather than explicit. If someone reads the `@theme` block, there is no indication that those values get overridden at runtime.

Caution: None of these projects use Tailwind v4's `@theme` block. OTS is ahead of the curve here, which means there is no battle-tested pattern to copy. The `@theme` approach is cleaner than Zitadel's SCSS fallbacks, but OTS needs to own the debugging story when `@theme` defaults and JS-injected overrides interact unexpectedly.

Recommendation for corner_style and font_family: OTS already has `cornerStyleClasses` and `fontFamilyClasses` lookup maps (in
`/Users/d/Projects/opensource/onetime/onetimesecret/src/schemas/models/domain/brand.ts`), and components like `SecretConfirmationForm.vue`, `SecretDisplayCase.vue`, and
`SecretPreview.vue` consume them via computed properties. The pattern is consistent but scattered -- each component independently does `brandSettings?.corner_style as
CornerStyle` with its own fallback. None of the surveyed competitors do per-component class computation like this. Zitadel would express corner radius as a CSS variable;
Rallly would not support it at all. The OTS pattern of Tailwind class switching per component is viable but would benefit from centralization. The `identityStore` already
has `cornerClass` and `fontFamilyClass` computeds -- the branded secret components should use those instead of re-deriving from raw `brandSettings`.

## 2. Runtime vs. Build-Time

Survey findings:

- Rallly: Build-time only. Env vars parsed at startup, injected during SSR. Changing brand requires redeployment.
- Zitadel: Runtime, but with a generation step. `ActivateLabelPolicy` triggers CSS file generation. The artifact is static until next activation. Runtime in terms of "no
  rebuild needed," but not runtime in terms of "changes apply instantly to all open tabs."
- Documenso: Runtime, immediate. Save = live. No CSS generation; branding is logo/text substitution.

OTS position: OTS is fully runtime -- the `useBrandTheme` composable watches `identityStore.primaryColor` reactively and regenerates the palette on change. This is more
dynamic than any of the three surveyed projects. The palette generation runs on every page load in the client.

The Zitadel insight that matters: The survey specifically calls out: "OTS currently regenerates the 44-var palette per request. An activation trigger (even if 'activation'
is just 'save') would let that generation happen once." This is worth internalizing. The `memoizedGeneratePalette` in `useBrandTheme.ts` partially addresses this
(single-entry cache by hex), but the memo does not persist across page loads. Every fresh navigation regenerates from scratch.

Potential approach: Pre-compute the palette on the backend (or at config save time) and serve the 44 hex values as part of the bootstrap payload, rather than shipping the
hex and having every client re-derive the palette. The color math is deterministic; there is no reason for 1000 clients to independently compute the same 44 colors from
the same input hex. Zitadel generates a CSS file; OTS could embed a pre-computed palette object in the bootstrap JSON.

Caution: Do not move to a build-time-only model. Rallly's readonly admin UI with "set the env var" messages is the survey's clearest cautionary tale. The runtime
capability OTS already has is a genuine advantage for self-hosted operators.

## 3. Component Architecture for Design Tokens

Survey findings:

- Zitadel: Design tokens (colors, fonts) flow through CSS variables. Components never reference brand config directly -- they use semantic classes that resolve through the
  CSS cascade. Font customization uses `@font-face` injection in the generated CSS file.
- Rallly: Thin layer -- `bg-primary` and `text-primary` classes resolve to CSS vars. Components do not know they are branded.
- Documenso: No CSS theming. Components check `brandingEnabled` flags and conditionally render different markup.

OTS current state for corner_style and font_family: The schema at `/Users/d/Projects/opensource/onetime/onetimesecret/src/schemas/models/domain/brand.ts` defines:

```ts
cornerStyleClasses: Record<CornerStyle, string> = {
  [CornerStyle.ROUNDED]: 'rounded-md',
  [CornerStyle.PILL]: 'rounded-xl',
  [CornerStyle.SQUARE]: 'rounded-none',
};

fontFamilyClasses: Record<FontFamily, string> = {
  [FontFamily.SANS]: 'font-sans',
  [FontFamily.SERIF]: 'font-serif',
  [FontFamily.MONO]: 'font-mono',
};
```

These are consumed in at least 6 components (`SecretConfirmationForm`, `SecretDisplayCase`, `SecretPreview`, `ShowSecret`, `UnknownSecret`, `BaseUnknownSecret`, `BrandedMastHead`), each
with its own computed property that does the same `brandSettings?.corner_style as CornerStyle` cast and fallback.

The Zitadel CSS-variable approach would eliminate this duplication. Instead of each component computing a Tailwind class from the brand setting, `useBrandTheme` (or a new
composable) could set CSS variables like `--brand-border-radius` and `--brand-font-family`, and components would use a single Tailwind utility that references those vars.
However, this creates tension with Tailwind's philosophy -- Tailwind does not natively map `rounded-{var}` to a CSS custom property. You would need `@theme` entries for border
radius and font family, similar to the color palette.

More pragmatic path: Keep the Tailwind class switching, but centralize it. The `identityStore` already exposes `cornerClass` and `fontFamilyClass`. Components that currently
derive these from raw `brandSettings` should consume the store's computeds instead. This reduces the casting and fallback logic to a single location.

## 4. Logo / Favicon Handling

Survey findings:

- Rallly: Env vars for logo URLs (`LOGO_URL`, `LOGO_URL_DARK`, `LOGO_ICON_URL`). Rendered as `<img>` tags with `dark:hidden` / `dark:block` toggling. Falls back to bundled SVG.
- Zitadel: Upload via API. Separate logo and icon per theme (light/dark). Assets stored in a blob store, served through a dynamic resource handler with request-scoped
  org/instance resolution. `<link>` to generated CSS file; logos are `<img>` in login templates.
- Documenso: Upload via form. Stored as JSON-stringified file reference. Served through dedicated API endpoints (`/api/branding/logo/team/{teamId}`) with Cache-Control:
  `max-age=3600, stale-while-revalidate=86400`.

OTS current state: The schema defines `logo_url`, `logo_dark_url`, and `favicon_url` as optional URL strings. The `identityStore` has a `logoUri` computed. The `DefaultLogo.vue`
component exists with hardcoded SVG paths. The colonel admin view shows domain logos.

Gaps:

1. No dark-mode logo toggling. Rallly's `dark:hidden` / `dark:block` pattern is the cleanest approach for Tailwind projects. OTS has `logo_dark_url` in the schema but no
   evidence of dark-mode switching in logo rendering.
2. No favicon runtime replacement. The schema has `favicon_url` but no code sets `<link rel="icon">` dynamically. This is a `document.head` manipulation -- straightforward but
   easy to forget. Zitadel handles it through the icon asset pipeline; Rallly handles it through the `logoIcon` env var.
3. No cache strategy for uploaded logos. Documenso's stale-while-revalidate approach is sensible. OTS serves logos through the `/imagine` route but there is no visible cache
   header strategy on the frontend side.

Recommendation: Implement dark-mode logo toggling using Rallly's pattern (two `<img>` elements, toggled by dark: variant classes). For favicon, a small utility function in
`useBrandTheme` or a dedicated composable that sets `document.querySelector('link[rel="icon"]').href` when `favicon_url` changes. Both are low-effort, high-polish additions.

## 5. FOUC Prevention

Survey findings:

- Rallly: SSR injects CSS vars onto `<html>` during server render. No FOUC because the initial HTML already carries the brand colors. This is the gold standard but requires
  SSR.
- Zitadel: Static CSS file loaded via `<link>` in `<head>`. Browser blocks rendering until the stylesheet loads (standard CSS blocking behavior). No FOUC.
- Documenso: No CSS theming, so no FOUC concern. Logo swaps may flash the default logo briefly, but it is asset substitution, not color theming.

OTS vulnerability: OTS is a client-rendered SPA. The sequence is:

1. Browser loads HTML with `<link>` to compiled CSS (which contains `@theme` defaults -- the OTS orange `#dc4a22`).
2. Vue hydrates, Pinia stores initialize from bootstrap data.
3. `useBrandTheme()` runs in `App.vue`, watches `primaryColor`, calls `applyPalette()`.
4. 44 `style.setProperty()` calls override the `@theme` defaults.

Between steps 1 and 4, the user sees the default OTS orange. For a white-labeled instance with a blue brand, this is a visible flash of orange-to-blue. The duration
depends on JS parse/execute time, but it is noticeable on slower connections.

Mitigation strategies (from the landscape and general practice):

1. Inline a `<script>` in the HTML `<head>` that reads the brand color from a known source (a cookie, a `<meta>` tag injected by the backend, or a global variable on `window`) and
   sets the 44 CSS vars before the first paint. This is the pattern used by dark-mode toggles across the industry. OTS already has `window.__ots_bootstrap` -- if
   `brand_primary_color` is on that object, a small synchronous script in `<head>` could pre-apply the palette. The challenge: the palette generation code is complex (oklch
   math). Options:

- Pre-compute the palette server-side and embed all 44 values in the bootstrap object.
- Ship a minimal inline version of the palette generator (increases HTML size).

2. Hide content until brand is applied. Set `opacity: 0` on `<body>` in CSS, then `opacity: 1` after `useBrandTheme()` runs. This trades FOUC for a brief blank screen -- usually
   acceptable if the delay is under 100ms.
3. Accept the flash for non-default brands. For the common case (OTS default brand), there is no flash because `isDefaultColor()` returns true and `clearOverrides()` is a
   no-op. The flash only matters for custom-branded instances. If those are a minority of deployments, the investment may not be justified yet.

Caution: Strategy 1 (inline script) introduces a coupling between backend HTML templating and frontend brand logic. If the palette algorithm changes, both the inline
script and `brand-palette.ts` must stay in sync. Pre-computing the palette server-side and embedding the result avoids this -- the frontend just applies key-value pairs
without understanding how they were derived.

## 6. Accessibility

Survey findings:

- Rallly: `adjustColorForContrast()` iteratively adjusts the dark variant to achieve WCAG AA 3.0+ contrast ratio (up to 20 iterations). This is the only project that
  automatically enforces contrast.
- Zitadel: No automatic contrast validation. The 11-shade palette is generated mechanically; operators can choose colors that fail WCAG. The admin UI provides a preview
  but no contrast warnings.
- Documenso: No color theming, so no contrast concern for brand colors. Logo alt text is present.

OTS current state: The oklch palette generator in `brand-palette.ts` does not validate contrast ratios. It generates shades mechanically based on lightness curves. An
operator could supply a brand color whose 500 shade against white text fails WCAG AA (4.5:1 for normal text).

Risks:

1. `bg-brand-500` with white text. If the brand color is light (e.g., `#f0c040`), the 500 shade may not provide sufficient contrast with white or near-white text. OTS uses
   `text-white` on `bg-brand-*` backgrounds in several components.
2. `button_text_light` exists in the schema as a boolean that defaults to true. This suggests someone anticipated the need to flip text color, but it is a manual toggle
   rather than an automatic contrast check.
3. Dark mode. The `@theme` block does not define separate dark-mode brand values. The palette has 11 shades, so dark-mode components can use lighter shades (e.g., `brand-300`
   for text on dark backgrounds), but this mapping is left to individual component authors.

Recommendations:

- Add a contrast validation utility that takes the generated palette and checks key pairings (e.g., `brand-500` vs white, `brand-700` vs white, `brand-200` vs `brand-900`).
  Rallly's iterative approach is one model. A simpler approach: compute relative luminance from the generated hex and warn in the admin UI if the 500 shade fails 4.5:1
  against white.
- Auto-derive `button_text_light` from the palette rather than requiring manual toggle. If `brand-500` luminance > 0.5 in oklch, set button text to dark; otherwise light. The
  oklch lightness value is already available since that is the color space OTS works in.
- Document shade usage guidance for component authors: which shades are safe for text-on-background vs background-under-text, in both light and dark modes.

## Summary of Priorities

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┬──────────────────────────────────┬────────┐
│                                           Finding                                           │             Urgency              │ Effort │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Centralize cornerClass/fontFamilyClass to identityStore (stop re-deriving in 6+ components) │ Medium                           │ Low    │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ FOUC: pre-compute palette server-side, embed in bootstrap                                   │ High for white-label deployments │ Medium │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Dark-mode logo toggling (dark:hidden / dark:block)                                          │ Medium                           │ Low    │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Favicon runtime replacement                                                                 │ Low                              │ Low    │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Contrast validation in admin UI                                                             │ Medium                           │ Medium │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Auto-derive button_text_light from luminance                                                │ Low                              │ Low    │
├─────────────────────────────────────────────────────────────────────────────────────────────┼──────────────────────────────────┼────────┤
│ Consider moving palette pre-computation to backend/save-time (Zitadel pattern)              │ Low (performance)                │ Medium │
└─────────────────────────────────────────────────────────────────────────────────────────────┴──────────────────────────────────┴────────┘
```

## What to Avoid

1. Do not adopt Rallly's env-var-only model. The survey explicitly calls it a "cautionary tale about stopping at env vars." OTS's runtime capability is a strength.
2. Do not generate a separate CSS file a la Zitadel. That pattern makes sense for Zitadel's multi-tenant architecture with asset storage infrastructure. For OTS's
   single-tenant self-hosted model, the inline `style.setProperty()` approach is simpler and sufficient. The FOUC concern is better solved by pre-computing the palette in the
   bootstrap payload.
3. Do not adopt Documenso's all-or-nothing inheritance pattern. OTS already has a 3-step fallback chain (domain brand -> installation config -> hardcoded default) that is
   more granular. Preserve that.
4. Do not introduce a draft/preview/activate lifecycle yet. The survey notes that for single-tenant self-hosted deployments, preview is ceremony. OTS's `SecretPreview.vue`
   component already provides a visual preview in the brand settings UI. A full state machine is unnecessary overhead at this stage.
