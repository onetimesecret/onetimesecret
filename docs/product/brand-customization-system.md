# Brand Customization System — Product Bible

Version: 1.1 | Status: Living Document | Owner: Product/Engineering
PRD Reference: PR #2483 — Centralize brand customization system
Last Audit: 2026-02-08

## Overview

The brand customization system enables Onetime Secret installations and custom domains
to express a complete visual identity through configuration alone — no code changes, no
rebuilds. A single hex color generates an 11-shade oklch palette (44 CSS vars across 4
palette variants) at runtime. Product name, typography, corner style, and support contact
flow through i18n and CSS variables.

The system's north star: **Onetime Secret's own design (`#dc4a22`, Zilla Slab, the 秘
logo) should be expressible purely as a configuration of this system.** If we can eat our
own dogfood, every self-hosted operator and custom-domain customer gets the same level of
polish.

---

## Table of Contents

1. [Problem Statement](#1-problem-statement)
2. [User Personas](#2-user-personas)
3. [Architecture](#3-architecture)
4. [Current Config Fields](#4-current-config-fields)
5. [Dogfood Readiness Assessment](#5-dogfood-readiness-assessment)
6. [Competitive Landscape](#6-competitive-landscape)
7. [Gap Analysis](#7-gap-analysis)
8. [Phased Roadmap](#8-phased-roadmap)
9. [Design Token Architecture](#9-design-token-architecture)
10. [Dual-Lifecycle Model](#10-dual-lifecycle-model)
11. [Accessibility & Contrast](#11-accessibility--contrast)
12. [Security Considerations](#12-security-considerations)
13. [Email Branding](#13-email-branding)
14. [Operator Documentation](#14-operator-documentation)
15. [Open Questions](#15-open-questions)
16. [Document Management Notes](#16-document-management-notes)
17. [Decision Log](#17-decision-log)
18. [Change History](#18-change-history)

---

## 1. Problem Statement

**Before PR #2483**: ~60 hardcoded `#dc4a22` occurrences across 30+ files. Three
disconnected branding subsystems (CSS @theme, JS identityStore, backend
BrandSettingsConstants). Self-hosted operators had to fork and find-replace. Custom domain
customers got inconsistent branding — their color reached the MastHead but not the 80+
Tailwind-class components.

**After this system** (current state): Color flows through a unified pipeline. Product name
flows through i18n. But non-color dimensions (logo, favicon, fonts, corner style runtime)
still have gaps.

**Impact of not completing**: Self-hosted operators see OTS branding despite configuring
their own. Mid-tier SaaS customers can't fully express their brand on custom domains.
Enterprise white-label prospects hit a ceiling.

---

## 2. User Personas

### Self-Hosted Operator (Install-Time Customization)
- **Role**: DevOps/IT at a company running their own OTS instance
- **Pain points**: Wants zero OTS branding visible to their users. Needs ENV/config-only
  setup — no frontend rebuilds, no forking.
- **Goals**: Set 5-10 config values and have the entire product reflect their brand
- **Customization scope**: Everything — colors, logo, name, emails, favicon, fonts,
  error pages, TOTP issuer

### Custom Domain Customer (Page-Load-Time Customization)
- **Role**: Mid-tier SaaS customer with their own domain (e.g., secrets.acme.com)
- **Pain points**: Wants their brand visible when employees/clients use the service.
  Currently limited to color and name in the domain settings panel.
- **Goals**: Brand color, logo, and product name on their custom domain pages
- **Customization scope**: Subset of full customization — color, name, logo. Not fonts,
  corner style, or deep theming (those remain install-level).

### OTS Product Team (Dogfood Operator)
- **Role**: The OTS team itself, running onetimesecret.com
- **Pain points**: Must validate that the brand system works by using it for the primary
  product. Currently, OTS's own identity leaks through hardcoded defaults rather than
  flowing through configuration.
- **Goals**: OTS design expressed as config. Default installation is neutral.
  onetimesecret.com's brand is applied via the same system any operator would use.

---

## 3. Architecture

### Three-Layer Brand Resolution

```
┌─────────────────────────────────────────────────────────────┐
│                    Page Render                              │
│                                                             │
│  primaryColor = domain_branding.primary_color               │
│               ?? bootstrapStore.brand_primary_color          │
│               ?? DEFAULT_PRIMARY_COLOR                       │
│                                                             │
│  Layer 1: Per-Domain (Redis)     ← page-load-time           │
│  Layer 2: Per-Installation (ENV/config) ← install-time      │
│  Layer 3: Hardcoded Fallback     ← compile-time             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

```
Install-Time Path:
  ENV vars → config.defaults.yaml → OT.conf → ConfigSerializer
  → bootstrap payload → bootstrapStore → useBrandTheme → CSS vars on :root

Page-Load-Time Path:
  Redis brand_settings → API response → identityStore
  → useBrandTheme → CSS vars on :root (overrides install defaults)

Email Path:
  OT.conf → TemplateContext helpers (brand_color, product_name, support_email)
  → ERB templates → inline hex + text (no CSS vars — email clients don't support them)
```

### Key Design Decision: Shared Mechanism

Both lifecycle paths resolve through the same CSS custom property layer.
Tailwind v4 is 100% CSS — the `@theme` block in `style.css` defines build-time defaults,
and `useBrandTheme` overrides those same `--color-brand-*` variables at runtime.

This is architecturally rare. Most OSS SaaS projects (Mattermost, Chatwoot) bolt
per-tenant theming on as a separate system from install-level branding, creating
maintenance burden and feature asymmetry. OTS's unified approach means every new brand
config field automatically works at both levels.

### Key Files

| File | Role |
|------|------|
| `src/utils/brand-palette.ts` | oklch palette generator — 44 CSS vars from 1 hex |
| `src/shared/composables/useBrandTheme.ts` | Watches identityStore, injects/removes CSS vars on :root |
| `src/shared/constants/brand.ts` | Frontend defaults and neutral brand constants |
| `src/shared/stores/identityStore.ts` | Holds current domain's brand settings |
| `src/shared/stores/bootstrapStore.ts` | Holds installation-level brand config |
| `src/assets/style.css` | `@theme` block — build-time Tailwind defaults |
| `etc/defaults/config.defaults.yaml` | Backend brand config with ENV overrides |
| `lib/onetime/models/custom_domain/brand_settings.rb` | Per-domain brand in Redis |
| `lib/onetime/mail/views/base.rb` | Email template brand helpers |
| `apps/web/core/views/helpers/initialize_view_vars.rb` | View bootstrapper |

---

## 4. Current Config Fields

The `brand:` section in `config.defaults.yaml` exposes 9 fields:

| Field | Type | Default | ENV Override | Purpose |
|-------|------|---------|-------------|---------|
| `primary_color` | hex string | `#dc4a22` | `BRAND_PRIMARY_COLOR` | Generates 44-shade oklch palette |
| `product_name` | string | `Onetime Secret` | `BRAND_PRODUCT_NAME` | Displayed in UI, emails, TOTP |
| `corner_style` | enum | `rounded` | `BRAND_CORNER_STYLE` | `rounded` / `square` / `pill` |
| `font_family` | enum | `serif` | `BRAND_FONT_FAMILY` | `sans` / `serif` / `mono` |
| `button_text_light` | boolean | `true` | `BRAND_BUTTON_TEXT_LIGHT` | Light or dark text on brand buttons |
| `support_email` | string | `support@onetimesecret.com` | `BRAND_SUPPORT_EMAIL` | Contact email in UI and emails |
| `product_domain` | string | — | `BRAND_PRODUCT_DOMAIN` | Canonical domain for the product |
| `allow_public_homepage` | boolean | `true` | `BRAND_ALLOW_PUBLIC_HOMEPAGE` | Show public landing page |
| `allow_public_api` | boolean | `true` | `BRAND_ALLOW_PUBLIC_API` | Expose public API |

### Fields That Work End-to-End
- `primary_color` — Fully functional. Generates palette, flows through CSS vars.
- `product_name` — Mostly functional. Flows through i18n in most places. Some fallbacks
  still hardcode "Onetime Secret."
- `support_email` — Flows to frontend and most email templates. One hardcoded instance
  in `error.rue`.
- `button_text_light` — Works for brand buttons via CSS.
- `allow_public_homepage`, `allow_public_api` — Work as feature toggles.

### Fields With Gaps
- `corner_style` — Schema exists, `CornerStyle` enum defined, but **no runtime
  mechanism** applies it to component classes. Components hardcode `rounded-md`,
  `rounded-lg`, etc.
- `font_family` — Config field is read but not applied at runtime. All three options
  (`sans`/`serif`/`mono`) currently resolve to Zilla Slab because the `@font-face`
  declarations in `style.css` always load Zilla Slab and the `.font-brand` utility
  always maps to it. No conditional font loading exists.

---

## 5. Dogfood Readiness Assessment

**Overall: ~70% ready.** Color system is production-grade. Non-color dimensions have
significant gaps.

### What's Working

| Area | Status | Evidence |
|------|--------|----------|
| Color palette generation | Production-ready | 44 CSS vars, oklch, gamut clipping |
| Brand CSS class adoption | Strong | 131 files, 404 `brand-*` class usages |
| Dark mode pairing | Good | Consistent `bg-brand-600 dark:bg-brand-500` patterns |
| Semantic color separation | Correct | red/amber/green for UX feedback, NOT brand |
| i18n product name | Mostly done | `$t()` with `{ product_name }` in most places |
| Email inline hex | Correct | `brand_color` helper outputs hex, not CSS vars |
| 3-layer fallback chain | Working | domain → install → default resolves correctly |
| MastHead logo chain | Well-designed | props → custom domain → config → default |

### What's Broken or Missing

Organized as three concentric rings:

#### Ring 1: Text Identity (cheapest fixes)

| Item | Location | Current | Should Be |
|------|----------|---------|-----------|
| bootstrapStore default | `bootstrapStore.ts:64` | `'Onetime Secret'` | Neutral or derived from config |
| usePageTitle default | `usePageTitle.ts:36` | `'Onetime Secret'` | Derive from bootstrapStore |
| TOTP issuer | `mfa.rb:24`, `totp.rb:23,51` | `'OneTimeSecret'` | Read from `brand.product_name` |
| Error page email | `error.rue:158` | `support@onetimesecret.com` | Template variable |
| Email support_email fallback | `base.rb:272` | `support@onetimesecret.com` | `support@example.com` |
| Email site_host fallback | `base.rb:288` | `onetimesecret.com` | `localhost` |
| View bootstrapper fallbacks | `initialize_view_vars.rb:168,181-183` | OTS-specific | Neutral defaults |
| Mail base.rb outer method | `base.rb:161-163` | `'Onetime Secret'` | Match inner method's chain |
| OtpSetupWizard fallback | `OtpSetupWizard.vue:37` | `'Onetime Secret'` | Use brand_product_name |
| OnetimeSecretIcon title | `OnetimeSecretIcon.vue:55` | `'Onetime Secret'` | Brand product_name |
| Config site_name default | `config.defaults.yaml:88` | `'One-Time Secret'` | Neutral |

#### Ring 2: Visual Identity (medium effort)

| Item | Status | Impact |
|------|--------|--------|
| Logo config field | Missing | Every white-label needs their own logo |
| Favicon | Hardcoded `#DC4A22` in SVG | Browser tab shows OTS orange |
| Email logo | Hardcoded `/img/onetime-logo-v3-xl.svg` in 9 templates | All emails show OTS 秘 icon |
| Zilla Slab font loading | Always loads regardless of `font_family` config | 100KB of OTS-specific assets |
| corner_style runtime | Config exists, nothing applies it | Components hardcode border-radius |
| Logo assets | All files are OTS-branded | No neutral default |
| Social preview image | Static OTS-branded PNG | og:image shows OTS when links shared |

#### Ring 3: Contextual Identity (long tail)

| Item | Status | Notes |
|------|--------|-------|
| GitHub/docs URLs | Hardcoded in ~10 components | Links to upstream repo |
| "Powered by" toggle | Not configurable | Enterprise white-label need |
| Terms/Privacy URLs | Not configurable | Compliance need |
| Dynamic PWA manifest | Static file | Can't reflect per-domain brand |
| `<meta name="theme-color">` | Not set from brand | Browser chrome color |
| Dynamic OG images | No generation pipeline | Social sharing previews |
| Error pages | Partially branded | `error.rue` hardcodes email |
| DnsWidget colors | ~20 hardcoded hex values | Third-party widget |
| Auth API response | Returns `'OneTimeSecret'` | Internal/diagnostic only |
| Deprecated mailer | Contains OTS fallbacks | `apps/web/auth/mailer.rb` should be deleted |

---

## 6. Competitive Landscape

### Comparison Matrix

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|-----------|-----|--------|------------|---------|----------|-----------|-----------|
| Single-color palette gen | 44-shade oklch | No | No | No | No | No | No |
| Color config | 1 hex → full palette | 2 colors | 20+ tokens (user) | CSS file edit | No | No | Embed theme |
| Logo | None | 3 slots | 1 (login) | Fork source | 3 variants | 1 (email) | None |
| Favicon | None | Yes | No | Fork | No | No | No |
| PWA manifest | None | Yes (full) | No | No | No | No | No |
| Product name | Yes | Yes | Yes (30 char) | ENV var | Yes | No | No |
| Font config | Yes | Nav theme | No | No | No | No | No |
| Corner style | Yes (broken) | No | No | No | No | No | No |
| Button text color | Yes | No | No | No | No | No | No |
| Support email | Yes | Help links | Support links | ENV var | No | No | No |
| Email branding | Color + alt text | Logo + toggle | Full HTML edit | No | No | Logo + footer | No |
| Login page | Toggle only | Full custom | Image + text + desc | Fork | No | No | N/A |
| Dark mode | Auto palette | Nav presets | 5 themes + custom | Light/dark tokens | LOGO_DARK | No | Light/dark embed |
| Powered by toggle | No | No | No | No | Widget URL | No | Embed removes |
| Admin brand UI | No | Yes (API too) | System Console | No | Super Admin | Org settings | No |
| Install vs tenant | Shared mechanism | Install only | Separate systems | Shared CSS | Separate systems | Shared schema | N/A |
| Runtime (no rebuild) | Yes | Yes | Restart for email | No (source edit) | Yes (DB) | Yes | N/A |

### Where OTS Leads

1. **Single-color palette generation** — No other project generates a full shade palette
   from one hex. GitLab needs 2 colors, Mattermost needs 20+, Cal.com needs manual hex
   editing. OTS's oklch approach is unique among surveyed projects.

2. **Shared customization mechanism** — Both install-time and page-load-time flow through
   the same CSS custom properties. Only Cal.com (just colors) and Documenso (just email)
   are similar. Most projects have separate systems for each level.

3. **Runtime palette without rebuild** — Most competitors require restart or rebuild for
   color changes. OTS applies instantly via CSS vars.

4. **Corner style and font family** — No other surveyed project offers these config fields.

5. **Button text contrast** — No other project has this nuance.

### Where OTS Trails

1. **Logo support** — GitLab (3 slots), Chatwoot (3 variants), Mattermost (1),
   Documenso (1), Rallly (2). OTS has zero.

2. **Favicon** — GitLab has it. Standard white-label expectation.

3. **Admin brand UI** — GitLab has a full Appearance admin panel with API. Mattermost has
   System Console. Chatwoot has Super Admin. OTS requires config file or ENV editing.

4. **Login page customization** — GitLab (title + description + logo), Mattermost
   (image + text + description). OTS only has a public homepage toggle.

5. **Email branding with logo** — 5 projects support logo in emails. OTS only has
   `brand_color` and `logo_alt` text.

### Potential Differentiators (Nobody Does These)

- **Brand preview mode** — No surveyed project offers admin-level preview of brand
  changes before applying. This could be a compelling feature.
- **Auto-contrast computation** — Automatic text color selection per shade using oklch
  lightness. Could make `button_text_light` config obsolete.
- **Single-source palette** — Already a differentiator. Could be enhanced with semantic
  aliases and dark theme auto-generation.

---

## 7. Gap Analysis

### By Priority

#### P0 — Self-hosted operator WILL see OTS branding despite configuring their own

These are blocking issues for the dogfood claim. A self-hosted install with
`BRAND_PRODUCT_NAME=Acme` and `BRAND_PRIMARY_COLOR=#0066FF` will still show:
- OTS 秘 logo in emails (9 templates)
- OTS orange favicon in browser tab
- "OneTimeSecret" in authenticator apps (TOTP)
- "support@onetimesecret.com" on error pages
- "Onetime Secret" in page titles (fallback)

#### P1 — Config fields exist but don't work

- `corner_style` has no runtime mechanism
- `font_family` always loads Zilla Slab
- ~12 backend fallback strings are OTS-specific

#### P2 — Missing config dimensions

Based on competitive analysis, these are expected by mature white-label systems:
- Logo URL (install + email)
- Favicon config
- "Powered by" toggle
- Terms/Privacy URLs
- Dynamic PWA manifest

#### P3 — Polish and differentiation

- Auto-contrast per shade
- Dynamic `<meta name="theme-color">`
- SVG favicon from brand color
- FOUC prevention
- Semantic color aliases
- Dynamic OG images
- Login page customization

### Gap Count by Ring

| Ring | Description | Items | Effort Estimate |
|------|-------------|-------|-----------------|
| Ring 1 | Text Identity | ~11 fallback strings | 1-2 days |
| Ring 2 | Visual Identity | 7 features | 3-5 days |
| Ring 3 | Contextual Identity | 10+ items | 1-2 weeks |

---

## 8. Phased Roadmap

### Phase 1: Neutralize Defaults (1-2 days)

**Goal**: A self-hosted install with brand config sees zero OTS text branding.

- [ ] Change all `'Onetime Secret'` fallbacks to `'My App'` in active codebase
- [ ] Change all `'support@onetimesecret.com'` fallbacks to `'support@example.com'`
- [ ] Change all `'onetimesecret.com'` fallbacks to `'localhost'`
- [ ] Make TOTP issuer read from `brand.product_name` (`mfa.rb`, `totp.rb`)
- [ ] Fix `error.rue` to use template variable for support email
- [ ] Audit deprecated `apps/web/auth/mailer.rb` for active references; delete if safe (see Open Question 8)
- [ ] Make `bootstrapStore` default `brand_product_name` neutral
- [ ] Make `usePageTitle` derive `DEFAULT_APP_NAME` from bootstrapStore

**Validation**: Deploy a test instance with custom brand config. Grep all rendered HTML,
emails, and TOTP QR codes for "Onetime Secret" or "onetimesecret" — zero matches expected.

### Phase 2: Visual Identity Config (3-5 days)

**Goal**: OTS's own visual identity is expressed through config. Default installation
renders with neutral visuals.

- [ ] Add `brand.logo_url` config field (ENV: `BRAND_LOGO_URL`). URL validation: `https://` only, no redirects, max 2MB. See Security (Section 12).
- [ ] Wire logo_url into MastHead as install-level fallback
- [ ] Wire logo_url into email templates (replacing hardcoded SVG path)
- [ ] Generate SVG favicon from brand primary color
- [ ] Add dynamic `<meta name="theme-color">` from brand color
- [ ] Implement `corner_style` runtime bridge (composable or CSS var)
- [ ] Conditional font loading — only load Zilla Slab when `font_family: serif`
- [ ] Create neutral default logo asset (geometric, uses brand color via currentColor)
- [ ] Write operator guide: `docs/operators/brand-customization.md` (see Section 14)

**Validation**: Two test instances side by side — one with OTS config, one with custom
brand. Both should look equally polished. The custom brand instance should have zero OTS
visual artifacts.

### Phase 3: Polish and Differentiation (1-2 weeks)

**Goal**: Best-in-class white-label system. Features no competitor offers.

- [ ] Auto-compute text contrast per shade (oklch lightness threshold L > 0.623)
- [ ] FOUC prevention — inject brand CSS inline in `<head>` before Vue hydrates
- [ ] "Powered by" toggle (`brand.show_attribution`)
- [ ] Configurable GitHub/docs URLs or conditional display
- [ ] Terms/Privacy URL config fields
- [ ] Dynamic PWA manifest endpoint
- [ ] Email dark mode resilience audit
- [ ] Social preview image generation (or configurable og:image URL)
- [ ] Brand preview mode in admin/settings

### Phase 4: Strategic (Future)

- [ ] Admin brand settings UI panel
- [ ] Login/signup page customization (background image, hero text)
- [ ] Custom CSS injection (escape hatch)
- [ ] Semantic color aliases (`--brand-surface`, `--brand-solid`, `--brand-text`)
- [ ] Dark theme auto-generation from same primary color
- [ ] Per-organization branding (multi-tenant within an installation)
- [ ] Custom email sender name/domain
- [ ] Font file upload

---

## 9. Design Token Architecture

### Current: Numbered Shades

```
--color-brand-50    (lightest)
--color-brand-100
--color-brand-200
--color-brand-300
--color-brand-400
--color-brand-500   (primary — the input hex)
--color-brand-600
--color-brand-700
--color-brand-800
--color-brand-900
--color-brand-950   (darkest)
```

Plus three additional palettes:
- `brandcomp-*` — complementary color (auto-generated)
- `branddim-*` — dimmed variant for dark contexts
- `branddimcomp-*` — dimmed complementary

### Future Consideration: Semantic Aliases

Other design systems (Radix, DaisyUI, Discourse) map numbered shades to purpose-driven
names. This makes the system self-documenting:

```
--brand-surface:       var(--color-brand-50)
--brand-surface-hover: var(--color-brand-100)
--brand-border:        var(--color-brand-200)
--brand-text-muted:    var(--color-brand-400)
--brand-solid:         var(--color-brand-500)
--brand-solid-hover:   var(--color-brand-600)
--brand-text:          var(--color-brand-900)
```

Developers would use `bg-brand-solid` instead of needing to know that 500 is the right
shade for a solid background. The numbered scale remains available for fine-tuning.

### DaisyUI's `-content` Pattern

For every background color, generate a matching readable text color:

```
--brand-solid:         var(--color-brand-500)
--brand-solid-content: white  (auto-computed from lightness)
```

This eliminates the manual `button_text_light` config field and scales to every shade.

### State of the Art: oklch Lightness Threshold

The palette generator already works in oklch. Adding auto-contrast is straightforward:

```
if (shade.lightness > 0.623) → dark text
if (shade.lightness <= 0.623) → light text
```

The threshold 0.623 closely predicts both WCAG 2.1 and APCA contrast requirements with
minimal computational overhead. CSS `contrast-color()` is emerging but currently only in
Safari Technology Preview.

---

## 10. Dual-Lifecycle Model

### Install-Time vs Page-Load-Time

| Dimension | Install-Time (Self-Hosted) | Page-Load-Time (Custom Domain) | Parity? |
|-----------|---------------------------|-------------------------------|---------|
| Primary color | ENV → config → bootstrap → CSS vars | Redis → identityStore → CSS vars | Yes |
| Product name | ENV → config → bootstrap → i18n | Redis → identityStore → i18n | Yes |
| Support email | ENV → config → bootstrap | Redis → identityStore | Yes |
| Logo | **Not configurable** | Custom domain logo in MastHead | **No** |
| Corner style | Config exists, **no runtime effect** | Same gap | Parity (broken) |
| Font family | Config exists, **Zilla Slab always loads** | Same gap | Parity (broken) |
| Email branding | Logo hardcoded, color configurable | No per-domain email logo | Parity |

### What Mid-Tier SaaS Customers Should Get

Based on competitive analysis, a reasonable feature set for custom domain customers:

**Should have** (page-load-time, per-domain):
- Brand primary color (already working)
- Product name (already working)
- Logo URL (planned — Phase 2)
- Favicon color (planned — Phase 2)

**Install-only** (self-hosted operators):
- Font family
- Corner style
- Support email
- Terms/Privacy URLs
- "Powered by" toggle
- PWA manifest details
- Custom CSS

**Rationale**: Color, name, and logo are the core brand elements customers expect to
customize. Typography and layout details are installation-level decisions that affect
the entire product experience.

### Performance: Runtime CSS Injection at Scale

CSS custom properties on `:root` are extremely fast — sub-millisecond for 44 variables.
The main concern is FOUC (Flash of Unstyled Content) when the composable applies vars
after Vue hydration.

**Mitigation**: Inject brand CSS in `<head>` as a `<style>` block during server-side
HTML generation, before Vue loads. The composable then becomes a no-op for the initial
paint and only activates on runtime changes (e.g., navigating between custom domains).

---

## 11. Accessibility & Contrast

### The Problem

Users pick arbitrary brand colors. The system must ensure text remains readable.

### Current Approach

Manual `button_text_light` boolean toggle in config. Works but:
- Requires the operator to understand contrast
- Only covers buttons, not all brand-colored surfaces
- Binary (light/dark) rather than per-shade

### Recommended Approach

Auto-compute text color per shade using oklch lightness:

```
For each generated shade:
  if L > 0.623 → assign dark text (#1a1a1a)
  if L <= 0.623 → assign light text (#ffffff)
```

This produces CSS variables like `--color-brand-500-text` alongside each `--color-brand-500`,
enabling components to always use readable text without manual configuration.

### Future: APCA

The Accessible Perceptual Contrast Algorithm accounts for font size and weight, producing
more nuanced contrast decisions than WCAG 2.1's simple luminance ratio. Worth considering
for Phase 4 when the system needs to handle arbitrary typography.

---

## 12. Security Considerations

Brand customization introduces user-controlled inputs that render in HTML, CSS, email
templates, and PWA manifests. Each input is an attack surface.

### Input Validation Requirements

| Field | Threat | Mitigation |
|-------|--------|------------|
| `primary_color` | CSS injection via malformed hex (e.g., `#fff; background: url(...)`) | Strict hex regex: `/^#[0-9a-fA-F]{3,8}$/` — already validated by Zod schema |
| `product_name` | XSS in HTML contexts, email header injection | HTML-escape on render. Max length 100 chars. No newlines. |
| `logo_url` (planned) | SSRF via `file://`, `data:`, internal IPs. Tracking pixels in emails. | Scheme allowlist: `https://` only. No redirects. Validate reachable. Max size 2MB. CSP `img-src` directive. |
| `support_email` | Email header injection, phishing | Validate email format. No newlines or special chars. |
| `font_family` | Enum — no injection risk | Already constrained to `sans`/`serif`/`mono` |
| `corner_style` | Enum — no injection risk | Already constrained to `rounded`/`square`/`pill` |
| Custom CSS (Phase 4) | XSS via `expression()`, `url()`, `@import`, `-moz-binding` | CSS sanitizer required. Strip all `url()`, `@import`, `expression()`, `behavior`, `-moz-binding`. Consider using a CSS parser (e.g., csstree) rather than regex. |
| Font file upload (Phase 4) | Executable code in font files. License violations. | Format allowlist (woff2 only). Size limit (500KB). No server-side font parsing. Serve via CDN with `Content-Type: font/woff2`. |
| PWA manifest (Phase 3) | XSS if `name`/`description` rendered in admin UI | JSON-encode all values. Never render manifest fields as raw HTML. |

### Content Security Policy (CSP) Implications

Adding configurable logos and fonts means CSP directives must be updated:

```
img-src 'self' https:;       ← allow external logo URLs (https only)
font-src 'self' https:;      ← allow external font URLs (Phase 4)
style-src 'self' 'unsafe-inline';  ← required for runtime CSS var injection
```

The `style-src 'unsafe-inline'` is already required by the current `useBrandTheme`
composable (it sets inline styles on `:root`). This is an acceptable tradeoff — the
alternative (nonce-based CSP) would require server-side rendering coordination.

### Email-Specific Security

- `brand_color` helper must validate hex format before outputting into inline styles
  (prevents CSS injection in email HTML)
- `logo_url` in email templates must be scheme-validated (no `javascript:`, `data:`)
- `product_name` in email subject/body must be HTML-escaped and free of newlines
  (prevents email header injection)

### Per-Domain Brand Validation

For page-load-time customization, brand settings come from Redis (set by custom domain
owners). These users are authenticated but potentially untrusted:

- All brand fields must be validated on write (domain settings API) not just on read
- Rate limit brand settings changes (prevent abuse of palette generation CPU)
- Log brand setting changes for audit trail

---

## 13. Email Branding

### Current State

- 9 HTML email templates use `brand_color` helper for inline hex (correct approach)
- `logo_alt` resolves to product name (correct)
- **Logo image URL** is hardcoded to `/img/onetime-logo-v3-xl.svg` in all 9 templates
- `support_email` is mostly configurable (one hardcoded instance in `error.rue`)

### Email-Specific Challenges

1. **No CSS variable support** — Email clients require inline styles. The backend
   correctly outputs hex, not CSS vars. This must remain.

2. **Dark mode in email** — Three behaviors across clients:
   - Gmail web: no change
   - Apple Mail: partial inversion (inverts light backgrounds)
   - Outlook dark: full inversion

3. **Logo dark mode** — Transparent PNG logos with padding survive both light and dark.
   OTS's current SVG logo has a solid background, which may look odd when inverted.

### Recommendations

- Add `brand.logo_url` config → wire into email templates
- Use transparent logos where possible
- Brand color for accents/buttons only (survives inversion better than large backgrounds)
- Consider `@media (prefers-color-scheme: dark)` blocks where supported
- Test with Litmus or Email on Acid for cross-client rendering

---

## 14. Operator Documentation

### Current State

No operator-facing documentation exists for brand customization. The only reference is
the `brand:` section in `config.defaults.yaml` (with ENV var comments) and this product
bible.

### What Operators Need

1. **Quick-start guide** — "Set these 3 ENV vars to customize your brand":
   - `BRAND_PRIMARY_COLOR` — hex color
   - `BRAND_PRODUCT_NAME` — your product name
   - `BRAND_SUPPORT_EMAIL` — your support email
   - Expected behavior: restart → brand applied everywhere

2. **Full reference** — All 9+ config fields with descriptions, defaults, examples, and
   which lifecycle level they affect (install-time vs page-load-time)

3. **Troubleshooting** — Common issues:
   - "My color changed but emails still show the old color" (email caching)
   - "My logo doesn't appear" (URL validation, CORS, CSP)
   - "The page flashes default colors before my brand loads" (FOUC)

4. **Brand validation CLI** — `bin/ots brand validate` command that checks:
   - Hex format valid
   - Logo URL reachable (if configured)
   - WCAG contrast warnings for chosen color
   - All brand fields resolved (no fallback to OTS defaults)

### Deliverables

- [ ] `docs/operators/brand-customization.md` — Phase 2 task
- [ ] `bin/ots brand validate` CLI command — Phase 3 task
- [ ] Inline help in `config.defaults.yaml` comments — Phase 1 (improve existing)

---

## 15. Open Questions

| # | Question | Owner | Blocker For | Status |
|---|----------|-------|-------------|--------|
| 1 | Should defaults be truly neutral (`'My App'`, `#0066FF` blue) or should the config file ship with OTS values and the code have neutral fallbacks? | Product | Phase 1 | Open |
| 2 | Should `corner_style` be a CSS custom property (`--brand-radius`) or a composable that returns Tailwind classes? | Engineering | Phase 2 | Open |
| 3 | What level of customization should page-load-time (custom domain) customers get? Logo? Font? Corner style? | Product | Phase 2 | Open |
| 4 | Should we build an admin Brand Settings UI, or is ENV/config sufficient for v1? | Product | Phase 4 | Open |
| 5 | Should `button_text_light` become auto-computed (removing the config field) or remain as a manual override? | Engineering | Phase 3 | Open |
| 6 | Implement server-side brand CSS injection in `<head>` or accept FOUC? | Engineering | Phase 3 | Open |
| 7 | Should email templates support a dark logo variant, or is transparent-background sufficient? | Design | Phase 3 | Open |
| 8 | Audit `apps/web/auth/mailer.rb` for active references before deletion | Engineering | Phase 1 | Open — prerequisite |

---

## 16. Document Management Notes

### Why Markdown (and Its Limits)

This document captures the full picture in a single file. Markdown works well for:
- Version control alongside code (git diff, PR review)
- Searchability (grep, IDE search)
- Portability (renders on GitHub, in editors, as HTML)

Where it falls short:
- **No interactive tables** — The comparison matrix would benefit from sortable columns
  and filtering. Consider exporting to a spreadsheet for stakeholder presentations.
- **No visual diffing** — When brand palettes change, a visual comparison tool (e.g.,
  Figma, Storybook) would show the actual color difference better than hex codes.
- **No task tracking** — The roadmap checklists here are snapshots. The canonical task
  tracker should be GitHub Issues with the `brand-system` label.
- **No living metrics** — Success metrics (adoption counts, hardcoded-value counts) go
  stale. Consider a script that counts `brand-*` class usage vs hardcoded colors and
  outputs a freshness report.

### Suggested Complementary Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| GitHub Issues | Task tracking for roadmap items | Create issues from Phase 1-4 checklists |
| GitHub Project Board | Visual progress across phases | Track phase completion |
| Storybook | Visual component library with brand variants | Phase 3+ |
| ADR files (`docs/architecture/decision-records/`) | Record key decisions from Open Questions | As questions are resolved |
| `brand-audit.sh` script | Automated count of hardcoded values | Run before each release |

### Keeping This Document Fresh

1. **After each phase completion**: Update the checklist, move items from "planned" to
   "done", update the readiness percentage.
2. **After competitive research**: Update Section 6 with new findings.
3. **After resolving an Open Question**: Move it to Section 15 (Decision Log) with the
   resolution.
4. **Quarterly**: Re-run the automated audit (grep for hardcoded values) and update
   Section 5 counts.

---

## 17. Decision Log

Decisions made during the brand system development. For significant architectural
decisions, create a formal ADR in `docs/architecture/decision-records/`.

| # | Date | Decision | Rationale | ADR |
|---|------|----------|-----------|-----|
| D1 | 2026-01 | Use oklch color space for palette generation | Perceptually uniform, handles gamut clipping, modern browser support | — |
| D2 | 2026-01 | Generate 4 palettes from 1 hex (brand, comp, dim, dimcomp) | Covers light/dark and accent needs without additional config | — |
| D3 | 2026-01 | Zod `.nullish()` not `.default()` for brand schema | Schema validates format only; the store resolves defaults. This preserves the 3-layer fallback chain. | — |
| D4 | 2026-01 | Remove `extend.colors` from `tailwind.config.ts` | Tailwind v4 uses CSS-only `@theme`. Config colors were a v3 holdover causing dual-source confusion. | — |
| D5 | 2026-01 | Replace `useBrandI18n` composable with standard `t()` | Standard i18n with explicit `{ product_name }` parameter is simpler and more consistent than a custom composable. | — |
| D6 | 2026-02 | Rename config key from `branding:` to `brand:` | Shorter, consistent with other config section naming (site:, redis:, etc.) | — |

---

## 18. Change History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-08 | Product/Engineering | Initial document from 4-agent dogfood audit |
| 1.1 | 2026-02-08 | Product/Engineering | Added security section (12), operator docs (14). Fixed palette count, font_family gap, open question ownership. Fresh-eyes review feedback. |

---

## References

- PR #2483: [Centralize brand customization system](https://github.com/onetimesecret/onetimesecret/pull/2483)
- Branch: `feature/brand-customization-system` (19 commits)
- Serena memory: `branding-centralization-architecture`
- Design system guide: `style.css` @theme block
- Email templates: `lib/onetime/mail/views/`
