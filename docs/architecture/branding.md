# Brand System Architecture

## Overview

The OTS brand system supports private-label deployments through a three-tier fallback chain that resolves brand values from the most specific (per-domain) to the most generic (neutral defaults). This architecture ensures branding never accidentally shows OTS identity when bootstrap fails or when running as a private-label instance.

## 3-Step Brand Fallback Chain

Brand values (primary color, product name, corner styles, etc.) are resolved through three sequential steps:

```
1. domain_branding (Redis)
   ↓ if null/absent
2. bootstrap config (backend OT.conf, populated from BRAND_* ENV vars)
   ↓ if null/absent
3. NEUTRAL_BRAND_DEFAULTS (frontend constants)
```

### Step 1: Per-Domain Branding (Redis)

**Source**: `domain_branding` from Redis via `CustomDomain` model
**Scope**: Individual custom domains
**Priority**: Highest

Custom domains can define their own brand identity stored in Redis. When present, these values take precedence over all other sources.

**Backend Storage**:
- Model: `lib/onetime/models/custom_domain/brand_settings.rb`
- Schema: `BrandSettings` Data.define with 22 fields
- Validation: Color accessibility (WCAG AA), URL formats, TTL ranges
- Redis structure: JSON-encoded hash per domain

**Frontend Access**:
- Delivered via `domain_branding` in bootstrap payload
- Parsed by identityStore using Zod schema
- Null/absent values fall through to step 2

### Step 2: Site-Wide Bootstrap Config (OT.conf)

**Source**: Backend configuration via `BrandSettingsConstants.global_defaults`
**Scope**: Installation-wide defaults
**Priority**: Medium

Site-wide brand defaults read from `OT.conf['brand']` section at runtime and delivered to the frontend via bootstrap payload. `OT.conf['brand']` is populated by the `brand:` block in `etc/defaults/config.defaults.yaml`, which exposes the `BRAND_*` ENV vars to the runtime config. Every key in that block defaults to `nil` so no OTS-branded values ship in the YAML — neutralization lives in the Ruby resolvers (`BrandSettingsConstants.defaults` / `.global_defaults`), per #3049. When `OT.conf['brand']` is absent (e.g. operators with a pre-#3048 `config.yaml` that doesn't include the block), the resolver falls through to neutral defaults.

**Backend Flow**:
```ruby
# lib/onetime/models/custom_domain/brand_settings.rb
BrandSettingsConstants.global_defaults
#=> { primary_color: OT.conf.dig('brand', 'primary_color'), ... }

# apps/web/core/views/helpers/initialize_view_vars.rb
view_vars['brand_primary_color'] = BrandSettingsConstants.global_defaults[:primary_color]

# apps/web/core/views/serializers/config_serializer.rb
output['brand_primary_color'] = view_vars['brand_primary_color']
```

**Frontend Flow**:
```typescript
// src/shared/stores/bootstrapStore.ts
// Bootstrap fields are derived from bootstrapSchema.parse({}); brand_*
// fields are optional and may be undefined when OT.conf['brand'] is absent.

// src/shared/stores/identityStore.ts
const primaryColor =
  primaryColorValidator.parse(brand.primary_color) ??
  bootstrapStore.brand_primary_color ??
  NEUTRAL_BRAND_DEFAULTS.primary_color
```

**Config Keys** (set via ENV vars; no defaults shipped):
- `BRAND_PRIMARY_COLOR` → `OT.conf['brand']['primary_color']` → `brand_primary_color`
- `BRAND_PRODUCT_NAME` → `brand_product_name`
- `BRAND_PRODUCT_DOMAIN` → `brand_product_domain`
- `BRAND_SUPPORT_EMAIL` → `brand_support_email`
- `BRAND_CORNER_STYLE` → `brand_corner_style`
- `BRAND_FONT_FAMILY` → `brand_font_family`
- `BRAND_BUTTON_TEXT_LIGHT` → `brand_button_text_light`
- `BRAND_ALLOW_PUBLIC_HOMEPAGE` → `brand_allow_public_homepage`
- `BRAND_ALLOW_PUBLIC_API` → `brand_allow_public_api`
- `BRAND_LOGO_URL` → `brand_logo_url`
- `BRAND_FAVICON_URL` → `/favicon.ico` route redirect (see variety pack below)
- `BRAND_APPLE_TOUCH_ICON_URL` → `brand_apple_touch_icon_url` (head `apple-touch-icon`)
- `BRAND_OG_IMAGE_URL` → `brand_og_image_url` (head `og:image` / `twitter:image`)
- `BRAND_TOTP_ISSUER` → MFA issuer label
- `BRAND_SIGNATURE_NAME` → email sign-off name (separate from `product_name`; falls back to the neutral i18n default `"Support Team"`)

### Step 3: Neutral Emergency Fallback

**Source**: `NEUTRAL_BRAND_DEFAULTS` constant
**Scope**: Frontend-only emergency fallback
**Priority**: Lowest

When bootstrap returns no brand data (the common case for self-hosted instances that have not set `BRAND_*` ENV vars), the frontend uses generic neutral defaults.

**Philosophy**: NEVER show OTS branding accidentally. Degrading to neutral blue (`#3B82F6`) "My App" theme prevents unintended advertising and supports private-label instances.

**Constants** (`src/shared/constants/brand.ts`):
```typescript
export const NEUTRAL_BRAND_DEFAULTS = {
  primary_color: '#3B82F6',        // Generic professional blue
  product_name: 'My App',          // Neutral placeholder
  button_text_light: true,
  corner_style: CornerStyle.ROUNDED,
  font_family: FontFamily.SANS,
  allow_public_homepage: true,
  allow_public_api: true,
} as const
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Backend (Ruby)                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────┐          ┌───────────────────────────┐    │
│  │   Redis Store    │          │   OT.conf (from ENV)      │    │
│  │                  │          │                           │    │
│  │  CustomDomain    │          │  brand:                   │    │
│  │   └─ branding {} │          │    primary_color: ENV     │    │
│  │                  │          │    product_name: ENV      │    │
│  └────────┬─────────┘          └───────────┬───────────────┘    │
│           │                                │                    │
│           │ Step 1                   Step 2│                    │
│           ▼                                ▼                    │
│  ┌────────────────────────────────────────────────────────┐     │
│  │      BrandSettingsConstants.global_defaults            │     │
│  │  Reads OT.conf['brand'] at runtime. Per-key absent     │     │
│  │  values pass through; no backend-side neutralization.  │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │      initialize_view_vars (InitializeViewVars)         │     │
│  │  Sets view_vars['brand_*'] from config/domain          │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         ConfigSerializer.serialize                     │     │
│  │  Transforms view_vars → bootstrap JSON payload         │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
└───────────────────────────┼─────────────────────────────────────┘
                            │ HTTP Response (bootstrap JSON)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Frontend (TypeScript)                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌────────────────────────────────────────────────────────┐     │
│  │          bootstrapStore (Pinia)                        │     │
│  │  Schema-derived defaults via bootstrapSchema.parse({}) │     │
│  │   - domain_branding (Step 1)                           │     │
│  │   - brand_primary_color (Step 2, optional)             │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │       identityStore.getInitialState()                  │     │
│  │  Implements 3-step fallback:                           │     │
│  │   1. domain_branding?.primary_color (Redis)            │     │
│  │   2. bootstrapStore.brand_primary_color (OT.conf/ENV)  │     │
│  │   3. NEUTRAL_BRAND_DEFAULTS.primary_color (#3B82F6)    │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │           useBrandTheme (Composable)                   │     │
│  │  Watches identityStore.primaryColor                    │     │
│  │  Generates 44 CSS variables via brand-palette.ts       │     │
│  │  Sets CSS vars on documentElement                      │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │            Vue Components                              │     │
│  │  Use Tailwind classes: bg-brand-500, text-brand-600    │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Code Examples

### Backend: Defining Per-Domain Branding

```ruby
# Create or update custom domain branding
domain = CustomDomain.new(display_domain: 'acme.example.com')
domain.extid = 'DOMAIN_EXTID'

# Set brand settings (stored in Redis)
domain.branding.primary_color = '#FF5733'
domain.branding.product_name = 'ACME Secrets'
domain.branding.corner_style = 'pill'
domain.save
```

### Backend: Setting Site-Wide Defaults via ENV

A `brand:` block ships in `etc/defaults/config.defaults.yaml` exposing the `BRAND_*` ENV vars; every key defaults to `nil` so no OTS branding is baked into shipped defaults. Operators set `BRAND_*` ENV vars to populate the block. The runtime resolver in `BrandSettingsConstants.global_defaults` reads `OT.conf['brand']` and falls back to neutral when the section is absent or its values are nil.

```bash
# Operator override path (set in deployment env, .env file, or process manager)
BRAND_PRIMARY_COLOR='#dc4a22'
BRAND_PRODUCT_NAME='ACME Secrets'
BRAND_PRODUCT_DOMAIN='secrets.acme.example.com'
BRAND_SUPPORT_EMAIL='support@acme.example.com'
BRAND_CORNER_STYLE='rounded'
BRAND_FONT_FAMILY='sans'
BRAND_BUTTON_TEXT_LIGHT='true'
BRAND_LOGO_URL='https://acme.example.com/logo.svg'
BRAND_TOTP_ISSUER='ACME Secrets'
```

### Frontend: Accessing Brand Values

```typescript
// src/shared/stores/identityStore.ts
import { useProductIdentity } from '@/shared/stores/identityStore'

const identity = useProductIdentity()

// Reactive brand values (already resolved via fallback chain)
console.log(identity.primaryColor)       // Step 1 → 2 → 3 resolved
console.log(identity.brand.product_name) // From domain_branding or null
console.log(identity.cornerClass)        // Computed Tailwind class
console.log(identity.fontFamilyClass)    // Computed font class
```

### Frontend: Using Brand CSS Variables

```vue
<template>
  <!-- Tailwind classes automatically use CSS variables -->
  <button class="bg-brand-500 hover:bg-brand-600 text-white">
    {{ $t('web.shared.submit') }}
  </button>

  <!-- Manual CSS variable access -->
  <div :style="{ backgroundColor: 'var(--color-brand-500)' }">
    Custom styled element
  </div>
</template>

<script setup lang="ts">
import { useBrandTheme } from '@/shared/composables/useBrandTheme'

// Composable watches identityStore and updates CSS vars
useBrandTheme()
</script>
```

## Key Files

### Backend
- `lib/onetime/models/custom_domain/brand_settings.rb` — Schema, validation, defaults
- `apps/web/core/views/helpers/initialize_view_vars.rb` — View var setup
- `apps/web/core/views/serializers/config_serializer.rb` — Bootstrap payload
- `apps/web/core/templates/partials/head-base.rue` — `mask-icon` uses `{{brand_primary_color}}`
- `lib/onetime/mail/views/base.rb` — `TemplateContext` helpers (`brand_color`, `logo_url`, `logo_alt`, `product_name`, `support_email`, `signature_name`)
- `etc/defaults/config.defaults.yaml` — Ships a `brand:` block with all-nil defaults; operators set `BRAND_*` ENV vars to populate it
- `etc/config.schema.yaml` — Top-level `brand:` schema (all keys optional, validated by `bin/ots validate`)

### Frontend
- `src/shared/stores/identityStore.ts` — 3-step fallback implementation
- `src/shared/stores/bootstrapStore.ts` — Bootstrap payload storage (schema-derived defaults)
- `src/shared/constants/brand.ts` — `NEUTRAL_BRAND_DEFAULTS`, deprecated `DEFAULT_BRAND_HEX`
- `src/shared/composables/useBrandTheme.ts` — CSS variable injection, favicon swap
- `src/utils/brand-palette.ts` — oklch palette generator (44 CSS vars)
- `src/schemas/contracts/custom-domain/brand-config.ts` — Zod schema (`brandSettingsCanonical`, 22 fields)
- `src/schemas/contracts/config/section/brand.ts` — Zod schema for the YAML brand section
- `src/schemas/contracts/bootstrap.ts` — Optional `brand_*` fields on `bootstrapSchema`

## CSS Variables (Generated Palette)

`generateBrandPalette(hex)` (in `src/utils/brand-palette.ts`) emits 44 CSS custom properties — 4 palette groups crossed with 11 shade steps. `useBrandTheme()` writes them to `document.documentElement.style`, so any consumer (Tailwind utility, inline style, raw CSS) can target them.

**Naming convention**: `--color-{prefix}-{shade}`

| Prefix | Source |
|---|---|
| `brand` | base hue at full chroma |
| `branddim` | base hue, lightness × 0.84, chroma × 0.90 |
| `brandcomp` | complement (base hue + 180°), full chroma |
| `brandcompdim` | complement, dimmed (same factors as `branddim`) |

**Shade steps** (11): `50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950`. `500` is the supplied base; `<500` lightens via a sqrt curve toward `L_MAX = 0.98`; `>500` darkens linearly toward `L_MIN = 0.25`.

```css
/* Examples */
--color-brand-500          /* base brand color (input hex) */
--color-brand-50           /* lightest tint of brand */
--color-branddim-700       /* dimmed brand, dark shade */
--color-brandcomp-500      /* complement at base lightness */
--color-brandcompdim-950   /* dimmed complement, darkest shade */
```

Tailwind `theme.colors.brand.500` etc. resolve to these vars (see `tailwind.config.ts`), so `bg-brand-500`, `text-branddim-300`, `border-brandcomp-700` all work.

## Performance

oklch palette generation runs once on mount (immediate watcher) and again whenever `identityStore.primaryColor` changes — typically a per-domain navigation or a brand-color save. The composable memoizes the most recent `(hex → 44-entry palette)` result in module scope (`src/shared/composables/useBrandTheme.ts`), so re-renders that don't change the input are O(1) lookups.

The math chain (hex → sRGB → linear → LMS → oklab → oklch + binary-search gamut clip per shade) is ~32 iterations × 11 shades × 4 scales per regeneration; negligible on modern hardware but observable in CPU traces during initial theme apply. In production, watch first-paint CPU on the `useBrandTheme` activation frame and any spike when an admin saves a new `primary_color` (live brand-color updates trigger one regeneration per change).

## Static Icon Assets (Favicon & Variety Pack)

The colour/value chain above resolves *strings* (hex colours, product names,
URLs). The favicon and the mobile/social icon pack are a parallel concern: a
set of **static files** served from the document root and referenced by the
HTML head. They follow the same neutralization philosophy — the OSS repo ships
brand-neutral assets so a self-hosted install never serves the OTS favicon.

**Pack** (`public/web/`): `favicon.svg`, `favicon.ico`, `apple-touch-icon.png`,
`icon-192.png`, `icon-512.png`, `safari-pinned-tab.svg`, `site.webmanifest`,
`social-preview.png` (og:image). All are generated from a single keyhole glyph
+ neutral palette by `scripts/branding/generate-favicons.mjs` (isolated from
the pnpm workspace so `sharp` never enters the app bundle).

**Override precedence** (favicon): per-custom-domain icon (Redis, unchanged)
→ site-level override → neutral bundled default. Site-level override is either
a `BRAND_*_URL` env var or a replacement file dropped into the brand directory
(`docker/branding/` at build time, or mounted over `public/web` at runtime).

**Wiring**:
- `apps/web/core/logic/page/get_favicon.rb` — `/favicon.ico` route; 302s to
  `brand.favicon_url` when set, else serves the neutral file; per-domain icons
  still take precedence.
- `apps/web/core/views/helpers/initialize_view_vars.rb` — resolves
  `brand_apple_touch_icon_url` and `brand_og_image_url` (override or neutral
  default path), and `show_default_svg_favicon`.
- **SVG favicon precedence gate**: browsers prefer an SVG `<link rel="icon">`
  over the `.ico`, so the static neutral `/favicon.svg` link is emitted **only**
  for canonical/default installs with no `brand.favicon_url`. On a custom domain
  (uploaded icon served by the `/favicon.ico` route) or a `brand.favicon_url`
  install (a `/favicon.ico` redirect), the SVG link is suppressed so it cannot
  shadow the higher-precedence favicon.
- `apps/web/core/templates/partials/head-base.rue` / `head.rue` — emit the
  full pack (`rel="icon"` SVG+ICO, `apple-touch-icon`, `manifest`, `mask-icon`,
  `og:image`, `twitter:image`).
- `lib/onetime/middleware/static_files.rb` — serves the root-level assets when
  running without a reverse proxy.
- `Dockerfile` — build-time `docker/branding/` overlay (no-op by default).

See [`docs/customization/branding-favicon.md`](../customization/branding-favicon.md)
for the operator-facing how-to.

## Special Cases

### Email Templates

Email templates cannot use CSS variables (email clients don't support custom properties). Brand colors must be inline hex values, sourced from runtime config via `TemplateContext` helpers — never template literals.

```ruby
# lib/onetime/mail/views/base.rb (TemplateContext)
def brand_color
  # Returns inline hex, NOT CSS var
  @data[:brand_color] ||
    OT.conf.dig('brand', 'primary_color') ||
    BrandSettingsConstants::DEFAULTS[:primary_color]
end
```

### Email Sign-off Name

Transactional emails close with a sign-off line. Historically this was the
hardcoded i18n string `"Delano"` baked into every `email.*.signature` key
across all 30 locales — it sat *below* the brand layer, so the private-label
neutralization (#3048/#3049) never reached it. The sign-off is now a brand
value, resolved by the `signature_name` `TemplateContext` helper:

```ruby
# lib/onetime/mail/views/base.rb (TemplateContext)
def signature_name
  @data[:signature_name] ||            # 1. optional per-message override
    conf_dig('brand', 'signature_name')  # 2. install-wide BRAND_SIGNATURE_NAME
end
```

Templates fall back to the neutral i18n default when it resolves to nil:

```erb
<%= h(signature_name || t('email.welcome.signature')) %>
```

Resolution order: per-message override → `BRAND_SIGNATURE_NAME` →
`email.*.signature` (`"Support Team"`). It is deliberately decoupled from
`product_name` so an operator can sign mail with a person or team
("Jane from Acme") without renaming the product everywhere else.

> A per-domain sign-off (settable on the `CustomDomain` brand record) is a
> natural extension, but is intentionally **not** implemented yet: no
> signature-bearing email is domain-scoped today, so the field would have no
> consumer. Add it together with the email path that consumes it.

### SecretPreview.vue

The secret preview component intentionally uses inline styles to show another domain's brand when previewing cross-domain secrets. It does NOT use CSS variables because it must display a different brand than the current context.

```vue
<!-- Shows the creating domain's brand, not current domain -->
<div :style="{
  backgroundColor: previewBrandColor,
  borderColor: previewBrandColor
}">
```

### DEFAULT_BRAND_HEX Deprecation

The `DEFAULT_BRAND_HEX` constant (`#dc4a22`, OTS orange) is deprecated for fallback use. `NEUTRAL_BRAND_DEFAULTS.primary_color` is the canonical fallback. `DEFAULT_BRAND_HEX` is retained only where displaying the OTS-orange specifically is the intent (e.g., palette-generator tests pinned to that hue).

## Validation Rules

Brand values undergo validation at write time (API endpoints):

### Color Validation
- Format: 6-digit or 3-digit hex (`#FF0000` or `#F00`)
- Accessibility: WCAG AA contrast ratio 3:1 minimum vs white (large text)
- Normalization: 3-digit expanded to 6-digit, uppercased

### Font Family
- Allowed values: `sans`, `serif`, `mono`
- Case-insensitive validation

### Corner Style
- Allowed values: `rounded`, `square`, `pill`
- Maps to Tailwind classes: `rounded-md`, `rounded-none`, `rounded-xl`

### URL Fields (logo_url, favicon_url)
- HTTPS URLs or relative paths starting with `/`
- Max length: 2048 chars
- Rejects protocol-relative URLs (`//`)

### Default TTL
- Positive integer (seconds)
- Validated on input, stored as integer

## Testing

### Backend Tests (Tryouts / RSpec)
```bash
# Brand settings validation
try tests/unit/ruby/try/models/brand_settings_try.rb
try tests/unit/ruby/try/models/brand_settings_wcag_try.rb

# Config serialization
pnpm run test:rspec spec/views/serializers/config_serializer_spec.rb
```

### Frontend Tests (Vitest)
```bash
# identityStore fallback chain
pnpm test src/shared/stores/__tests__/identityStore.spec.ts

# Brand palette generation
pnpm test src/utils/__tests__/brand-palette.spec.ts

# Brand theme composable
pnpm test src/shared/composables/__tests__/useBrandTheme.spec.ts

# Schema round-trip
pnpm test src/tests/schemas/contracts/brand-roundtrip.spec.ts
```

## Self-Hosted Upgrade Path

The neutral-defaults strategy means existing self-hosted instances render neutral blue (`#3B82F6`) and `'My App'` after upgrade unless operators set `BRAND_*` ENV vars. To preserve the previous OTS look-and-feel, set:

1. `BRAND_PRIMARY_COLOR` (e.g. `#dc4a22`) — required to override neutral blue.
2. `BRAND_PRODUCT_NAME` (e.g. `One-Time Secret`) — required to override `'My App'`.
3. `BRAND_SUPPORT_EMAIL`, `BRAND_LOGO_URL`, and siblings — set as needed.
4. Verify the bootstrap payload includes the corresponding `brand_*` fields.
5. Verify identityStore falls through to `NEUTRAL_BRAND_DEFAULTS` only when expected.
6. Confirm email templates render brand color inline via `TemplateContext` helpers.
7. Run WCAG AA validation on the chosen brand color.

## Private-Label Deployment Checklist

For deploying OTS as a private-label product:

- [ ] Set `BRAND_PRIMARY_COLOR` to your brand color
- [ ] Set `BRAND_PRODUCT_NAME` to your product name
- [ ] Set `BRAND_SUPPORT_EMAIL` for customer support
- [ ] Set `BRAND_LOGO_URL` (or upload a per-domain logo via the CustomDomain API)
- [ ] Test fallback chain: clear `BRAND_*` ENV, verify neutral theme appears
- [ ] Verify email templates show your brand color inline
- [ ] Check meta tags and page titles use the configured product name
- [ ] Test WCAG AA compliance for the chosen brand color
