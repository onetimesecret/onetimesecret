# Brand Customization for Self-Hosters

**Quick Start:** Set 3 environment variables, restart, done.

---

## Minimum Configuration

Create `.env.local` in your installation directory:

```bash
# Core brand identity
BRAND_PRIMARY_COLOR='#2563eb'      # Your brand color (hex)
BRAND_PRODUCT_NAME='YourBrand'     # Your product name
BRAND_SUPPORT_EMAIL='help@yourdomain.com'
```

Restart the backend:
```bash
source .env.sh && bin/backend restart
```

**Result:** Your installation displays your brand color, product name in the header and emails, and your support email in transactional messages.

---

## Complete Brand Configuration

All available environment variables:

```bash
# ── Core Brand Identity ──────────────────────────────────────
BRAND_PRIMARY_COLOR='#2563eb'      # Hex color → 44 CSS vars generated
BRAND_PRODUCT_NAME='YourBrand'     # Product name (SINGLE SOURCE OF TRUTH)
BRAND_PRODUCT_DOMAIN='yourdomain.com'
BRAND_SUPPORT_EMAIL='help@yourdomain.com'
BRAND_TOTP_ISSUER='YourBrand'      # MFA authenticator app display name

# ── Logo Configuration ───────────────────────────────────────
LOGO_URL='/img/logo.png'           # Path to PNG/SVG logo
LOGO_ALT='YourBrand - Secure Sharing'
LOGO_LINK='/'                      # Where logo clicks go

# Alternatively, use a Vue component for SVG-based logo:
# LOGO_URL='KeyholeLogo.vue'       # Dynamic logo component

# ── Brand Behavior ───────────────────────────────────────────
BRAND_CORNER_STYLE='rounded'       # rounded | square
BRAND_FONT_FAMILY='sans'           # sans | serif | mono
BRAND_BUTTON_TEXT_LIGHT=true       # true | false (button text color)
BRAND_ALLOW_PUBLIC_HOMEPAGE=true   # Show homepage to unauthenticated users
BRAND_ALLOW_PUBLIC_API=false       # Allow anonymous API access

# ── Email Sender Identity ────────────────────────────────────
FROM_EMAIL='no-reply@yourdomain.com'
FROM_NAME='YourBrand'
REPLYTO_EMAIL='help@yourdomain.com'
```

---

## Important: SITE_NAME is Deprecated

**❌ Don't use:** `SITE_NAME` (deprecated as of v0.24)
**✅ Use instead:** `BRAND_PRODUCT_NAME`

### Why the Change?

Previous versions had two competing configuration paths:
- `SITE_NAME` (legacy) → `site.interface.ui.header.branding.site_name`
- `BRAND_PRODUCT_NAME` (new) → `brand.product_name`

This caused confusion where both could control product name display.

**Migration:** If you currently use `SITE_NAME`, rename it to `BRAND_PRODUCT_NAME`. The backend will continue to read `SITE_NAME` for backward compatibility, but it's deprecated and may be removed in a future release.

---

## Logo Options

### Option 1: Static Image (PNG/SVG)

Traditional approach - point to an image file:

```bash
LOGO_URL='/img/custom-logo.png'
LOGO_ALT='YourBrand Logo'
```

Place your logo in `public/web/img/` (for local development) or serve from CDN.

**Pros:** Simple, works everywhere
**Cons:** Fixed size, no theme awareness

### Option 2: Vue Component (SVG)

Dynamic approach - use a Vue component:

```bash
LOGO_URL='KeyholeLogo.vue'
```

The system includes `KeyholeLogo.vue` component or you can create your own in `src/shared/components/logos/`.

**Pros:**
- Scalable (SVG)
- Theme-aware (responds to dark mode)
- Uses brand color automatically
- Smaller bundle size

**Cons:** Requires component development for custom designs

### Custom Logo Component

Create `src/shared/components/logos/YourLogo.vue`:

```vue
<script setup lang="ts">
import { type LogoConfig } from '@/types/ui/layouts';

const props = withDefaults(
  defineProps<LogoConfig & { isColonelArea?: boolean }>(),
  {
    size: 64,
    href: '/',
    isColonelArea: false,
  }
);
</script>

<template>
  <a :href="props.href">
    <!-- Your SVG logo here -->
    <svg :width="props.size" :height="props.size" class="text-brand-500">
      <!-- paths -->
    </svg>
  </a>
</template>
```

Set `LOGO_URL='YourLogo.vue'` and MastHead will dynamically load it.

---

## Logo Visibility Behavior

The product name text visibility depends on authentication state:

| State            | Display                                    |
|------------------|--------------------------------------------|
| Unauthenticated  | Logo + Product Name + Tagline             |
| Authenticated    | Logo only (conserves space for navigation) |
| Custom Domain    | Logo only (emphasizes custom branding)     |

You can override this with explicit props, but the defaults provide good UX.

---

## Color Palette System

Setting `BRAND_PRIMARY_COLOR` generates a complete 11-shade palette in oklch color space:

```
50  → Very light (backgrounds)
100-400 → Light shades
500 → Your primary color (buttons, links)
600-900 → Dark shades
950 → Very dark (text)
```

**44 CSS variables** are created:
- `.bg-brand-500` → backgrounds
- `.text-brand-500` → text
- `.border-brand-500` → borders
- Dark mode variants automatically generated

The palette is WCAG-contrast-safe. Dark shades maintain vibrancy through oklch's perceptual uniformity.

---

## WCAG Color Accessibility Requirements

Brand colors must meet WCAG AA standards for visual accessibility. The system validates your `BRAND_PRIMARY_COLOR` at boot to ensure sufficient contrast.

### Minimum Contrast Requirements

**3:1 contrast ratio** against white backgrounds for interactive elements (buttons, links, UI components).

This is the WCAG AA standard for "non-text contrast" (SC 1.4.11), which applies to:
- Button backgrounds
- Interactive controls
- Focus indicators
- Branded UI elements

**Why this matters:** Users with low vision, color blindness, or viewing screens in bright light need sufficient contrast to perceive interactive elements.

### Examples

**Passing colors** (3:1 or higher):
- `#dc4a22` (OTS orange) → 4.16:1 contrast on white
- `#2563eb` (blue) → 4.74:1 contrast on white
- `#059669` (green) → 3.42:1 contrast on white

**Failing colors** (below 3:1):
- `#fbbf24` (yellow) → 1.37:1 contrast on white
- `#f472b6` (light pink) → 1.96:1 contrast on white
- `#93c5fd` (light blue) → 1.64:1 contrast on white

### Validation Errors

If your brand color fails validation, the backend logs an error at boot:

```
[ERROR] Brand validation failed:
  - brand_primary_color '#fbbf24' has insufficient contrast (1.37:1).
    WCAG AA requires 3:1 minimum for UI components.
    Consider darkening the color or choosing a different shade.
```

The system will use fallback color `#dc4a22` (OTS orange) if validation fails.

### Testing Your Color

Before deployment, verify your brand color meets requirements:

**Online Contrast Checkers:**
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) — comprehensive tool with WCAG level indicators
- [Coolors Contrast Checker](https://coolors.co/contrast-checker) — clean interface, color picker
- [Accessible Colors](https://accessible-colors.com/) — suggests accessible alternatives

**Input your color** (hex format) and white background `#ffffff`. Look for the "Non-text" or "UI Component" result — it should show 3:1 or higher.

### Choosing Accessible Brand Colors

**Guidelines:**
- Prefer saturated, medium-to-dark colors for brand primaries
- Avoid pastels and very light tints as primary colors
- Test against both white and dark backgrounds if supporting dark mode
- The palette generator will create accessible light/dark shades automatically

**Quick rule:** If your color looks "vibrant" or "bold" to the eye, it likely passes. If it looks "pale" or "washed out," it probably fails.

---

## Verification Checklist

After configuration, verify your brand appears:

1. **Homepage:** Logo and product name visible
2. **Header (authenticated):** Logo displays, product name hidden
3. **Emails:** Transactional emails show your product name and support email
4. **API Specs:** OpenAPI docs use your product name (if `BRAND_PRODUCT_NAME` set at generation time)
5. **MFA Setup:** Authenticator app shows your `BRAND_TOTP_ISSUER`

**Check bootstrap endpoint:**
```bash
curl https://yourinstall.com/bootstrap/me | jq '.brand_product_name'
```

Should return your configured product name.

---

## Troubleshooting

### Product name still shows "OTS" or "Onetime Secret"

**Cause:** Backend not restarted after `.env.local` changes.
**Fix:** Configuration is frozen at boot. Restart:
```bash
source .env.sh && bin/backend restart
```

### Logo not displaying

**Cause 1:** File path incorrect
**Fix:** Verify file exists at `public/web/img/yourlogo.png`

**Cause 2:** Component not found (if using `.vue`)
**Fix:** Check component exists in `src/shared/components/logos/YourLogo.vue`

### Colors not applying

**Cause:** CSS build cache
**Fix:** Clear Vite cache and rebuild:
```bash
rm -rf node_modules/.vite
pnpm run build
```

### "Two product names" appearing

**Cause:** Both `SITE_NAME` and `BRAND_PRODUCT_NAME` set with different values
**Fix:** Remove `SITE_NAME`, use only `BRAND_PRODUCT_NAME`

---

## Advanced: Per-Domain Branding

For installations hosting multiple custom domains, see:
- [Custom Domain Organization Ownership](../../architecture/custom-domain-organization-ownership.md)
- [Brand Config Stratified](../../landscape/brand-config-stratified.md)

Custom domains can override `brand_primary_color`, `logo_url`, and `product_name` at the domain level, allowing multi-tenant branding.

---

## Reference

**Full system documentation:** [Brand Customization System](README.md)
**Implementation details:** [Part 4: Implementation](brand-part4-implementation.md)
**Configuration schema:** `etc/defaults/config.defaults.yaml` (search for `brand:`)

**Environment variable precedence:**
1. `.env.local` (never committed, deployment-specific)
2. `.env` (committed, shared defaults)
3. `config.defaults.yaml` (system defaults)

---

## Examples

### Corporate Self-Hosting

```bash
# Acme Corp deployment
BRAND_PRIMARY_COLOR='#ff0000'
BRAND_PRODUCT_NAME='Acme SecureShare'
BRAND_PRODUCT_DOMAIN='secureshare.acme.com'
BRAND_SUPPORT_EMAIL='it-support@acme.com'
LOGO_URL='/img/acme-logo.png'
BRAND_FONT_FAMILY='sans'
BRAND_CORNER_STYLE='square'
```

### Community Instance

```bash
# Privacy-focused community
BRAND_PRIMARY_COLOR='#6366f1'
BRAND_PRODUCT_NAME='PrivacyShare'
BRAND_PRODUCT_DOMAIN='privacyshare.org'
BRAND_SUPPORT_EMAIL='admin@privacyshare.org'
LOGO_URL='KeyholeLogo.vue'
BRAND_ALLOW_PUBLIC_HOMEPAGE=true
```

---

**Version:** 1.0 (2026-02-08)
**Status:** Living Document
**Feedback:** https://github.com/onetimesecret/onetimesecret/issues
