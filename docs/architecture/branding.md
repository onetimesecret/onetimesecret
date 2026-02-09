# Brand System Architecture

## Overview

The OTS brand system supports white-label/private-label deployments through a three-tier fallback chain that resolves brand values from the most specific (per-domain) to the most generic (neutral defaults). This architecture ensures branding never accidentally shows OTS identity when bootstrap fails or when running as a private-label instance.

## 3-Step Brand Fallback Chain

Brand values (primary color, product name, corner styles, etc.) are resolved through three sequential steps:

```
1. domain_branding (Redis)
   ↓ if null/absent
2. bootstrap config (backend OT.conf)
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
- Schema: `BrandSettings` Data.define with 21 fields
- Validation: Color accessibility (WCAG AA), URL formats, TTL ranges
- Redis structure: JSON-encoded hash per domain

**Frontend Access**:
- Delivered via `domain_branding` in bootstrap payload
- Parsed by identityStore using Zod schema
- Null/absent values fall through to step 2

### Step 2: Site-Wide Bootstrap Config (OT.conf)

**Source**: Backend configuration via `BrandSettingsConstants.defaults`
**Scope**: Installation-wide defaults
**Priority**: Medium

Site-wide brand defaults read from `OT.conf['brand']` section at runtime and delivered to the frontend via bootstrap payload.

**Backend Flow**:
```ruby
# lib/onetime/models/custom_domain/brand_settings.rb
BrandSettingsConstants.defaults
#=> { primary_color: OT.conf['brand']['primary_color'], ... }

# apps/web/core/views/helpers/initialize_view_vars.rb
view_vars['brand_primary_color'] = BrandSettingsConstants.global_defaults[:product_name]

# apps/web/core/views/serializers/config_serializer.rb
output['brand_primary_color'] = view_vars['brand_primary_color']
```

**Frontend Flow**:
```typescript
// src/shared/stores/bootstrapStore.ts
brand_primary_color: ref(bootstrap.brand_primary_color)

// src/shared/stores/identityStore.ts
const primaryColor =
  primaryColorValidator.parse(brand.primary_color) ??
  bootstrapStore.brand_primary_color ??
  NEUTRAL_BRAND_DEFAULTS.primary_color
```

**Config Keys**:
- `brand.primary_color` → `brand_primary_color`
- `brand.product_name` → `brand_product_name`
- `brand.corner_style` → `brand_corner_style`
- `brand.font_family` → `brand_font_family`
- `brand.button_text_light` → `brand_button_text_light`
- `brand.allow_public_homepage` → `brand_allow_public_homepage`
- `brand.allow_public_api` → `brand_allow_public_api`

### Step 3: Neutral Emergency Fallback

**Source**: `NEUTRAL_BRAND_DEFAULTS` constant
**Scope**: Frontend-only emergency fallback
**Priority**: Lowest

When bootstrap completely fails or returns no brand data, the frontend uses generic neutral defaults.

**Philosophy**: NEVER show OTS branding accidentally. Degrading to neutral blue (#3B82F6) "My App" theme prevents unintended advertising and supports white-label instances.

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
│  │   Redis Store    │          │   OT.conf (YAML)          │    │
│  │                  │          │                           │    │
│  │  CustomDomain    │          │  brand:                   │    │
│  │   └─ branding {} │          │    primary_color: #dc4a22 │    │
│  │                  │          │    product_name: OTS      │    │
│  └────────┬─────────┘          └───────────┬───────────────┘    │
│           │                                │                    │
│           │ Step 1                   Step 2│                    │
│           ▼                                ▼                    │
│  ┌────────────────────────────────────────────────────────┐     │
│  │         BrandSettingsConstants.defaults                │     │
│  │  Reads OT.conf at runtime, merges with DEFAULTS        │     │
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
│  │  Receives and stores bootstrap payload                 │     │
│  │   - domain_branding (Step 1)                           │     │
│  │   - brand_primary_color (Step 2)                       │     │
│  └────────────────────────┬───────────────────────────────┘     │
│                           │                                     │
│                           ▼                                     │
│  ┌────────────────────────────────────────────────────────┐     │
│  │       identityStore.getInitialState()                  │     │
│  │  Implements 3-step fallback:                           │     │
│  │   1. domain_branding?.primary_color (Redis)            │     │
│  │   2. bootstrapStore.brand_primary_color (OT.conf)      │     │
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

### Backend: Setting Site-Wide Defaults

```yaml
# config/config.defaults.yaml
brand:
  primary_color: '#dc4a22'
  product_name: 'OTS'
  corner_style: 'rounded'
  font_family: 'sans'
  button_text_light: true
  allow_public_homepage: false
  allow_public_api: false
```

### Frontend: Accessing Brand Values

```typescript
// src/shared/stores/identityStore.ts
import { useProductIdentity } from '@/shared/stores/identityStore'

const identity = useProductIdentity()

// Reactive brand values (already resolved via fallback chain)
console.log(identity.primaryColor)      // Step 1 → 2 → 3 resolved
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
- `lib/onetime/models/custom_domain/brand_settings.rb` - Schema, validation, defaults
- `apps/web/core/views/helpers/initialize_view_vars.rb` - View var setup
- `apps/web/core/views/serializers/config_serializer.rb` - Bootstrap payload
- `config/config.defaults.yaml` - Site-wide config source

### Frontend
- `src/shared/stores/identityStore.ts` - 3-step fallback implementation
- `src/shared/stores/bootstrapStore.ts` - Bootstrap payload storage
- `src/shared/constants/brand.ts` - NEUTRAL_BRAND_DEFAULTS, deprecated constants
- `src/shared/composables/useBrandTheme.ts` - CSS variable injection
- `src/utils/brand-palette.ts` - oklch palette generator (44 CSS vars)
- `src/schemas/models/domain/brand.ts` - Zod schema for validation

## Special Cases

### Email Templates

Email templates cannot use CSS variables (email clients don't support custom properties). Brand colors must be inline hex values.

```ruby
# apps/web/core/views/contexts/template_context.rb
def brand_color
  # Returns inline hex, NOT CSS var
  @domain&.branding&.primary_color ||
    BrandSettingsConstants.defaults[:primary_color]
end
```

### SecretPreview.vue

The secret preview component intentionally uses inline styles to show OTHER domain's brand when previewing cross-domain secrets. It does NOT use CSS variables because it must display a different brand than the current context.

```vue
<!-- Shows the creating domain's brand, not current domain -->
<div :style="{
  backgroundColor: previewBrandColor,
  borderColor: previewBrandColor
}">
```

### DEFAULT_BRAND_HEX Deprecation

The `DEFAULT_BRAND_HEX` constant (#dc4a22, OTS orange) is deprecated for fallback use. It remains only for:
- Palette generator tests (validate OTS color specifically)
- SecretPreview.vue (display other domain's brand)

DO NOT use `DEFAULT_BRAND_HEX` in new fallback logic. Use `NEUTRAL_BRAND_DEFAULTS.primary_color` instead.

## Validation Rules

Brand values undergo validation at write time (API endpoints):

### Color Validation
- Format: 6-digit or 3-digit hex (#FF0000 or #F00)
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

### Backend Tests (RSpec)
```bash
# Brand settings validation
pnpm run test:rspec spec/models/custom_domain/brand_settings_spec.rb

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
```

## Migration Notes

When migrating from OTS-branded defaults to neutral defaults:

1. Ensure `config/config.defaults.yaml` has explicit `brand:` section
2. Test bootstrap payload includes `brand_primary_color` field
3. Verify identityStore falls through to NEUTRAL_BRAND_DEFAULTS when appropriate
4. Check email templates use `brand_color` helper (inline hex, not CSS vars)
5. Update tests to expect blue (#3B82F6) when bootstrap fails, not orange (#dc4a22)

## White-Label Deployment Checklist

For deploying OTS as a white-label product:

- [ ] Set `brand.primary_color` in config to your brand color
- [ ] Set `brand.product_name` to your product name
- [ ] Configure `brand.support_email` for customer support
- [ ] Upload custom logo via CustomDomain API (if using custom domains)
- [ ] Test fallback chain: disable Redis, verify neutral theme appears
- [ ] Verify email templates show your brand color inline
- [ ] Check meta tags and page titles use configured product name
- [ ] Test WCAG AA compliance for chosen brand color
