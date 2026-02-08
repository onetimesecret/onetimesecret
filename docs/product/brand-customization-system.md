# Brand Customization System — Product Bible

Version: 1.4 | Status: Living Document | Owner: Product/Engineering
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

This document is organized in five parts: Context (the problem, personas, current state,
and gaps), Architecture (the solution), Cross-Cutting Concerns (accessibility, security,
QA), Implementation Specifics (email branding, operator docs), and Meta-Content (open
questions, decision log, document maintenance).

---

## Table of Contents

### Part 1: Context
- 1.1 [Problem Statement](#11-problem-statement)
- 1.2 [User Personas](#12-user-personas)
- 1.3 [Current State](#13-current-state)
- 1.4 [Dogfood Readiness Assessment](#14-dogfood-readiness-assessment)
- 1.5 [Gap Analysis: Ring Model](#15-gap-analysis-ring-model)

### Part 2: Architecture
- 2.1 [Core Architecture](#21-core-architecture)
- 2.2 [Design Token Architecture](#22-design-token-architecture)
- 2.3 [Dual-Lifecycle Model](#23-dual-lifecycle-model)

### Part 3: Cross-Cutting Concerns
- 3.1 [Accessibility & Contrast](#31-accessibility--contrast)
- 3.2 [Security Considerations](#32-security-considerations)
- 3.3 [Quality Assurance: Linting & Visual Regression](#33-quality-assurance-linting--visual-regression)

### Part 4: Implementation Specifics
- 4.1 [Email Branding](#41-email-branding)
- 4.2 [Operator Documentation](#42-operator-documentation)

### Part 5: Meta-Content
- 5.1 [Open Questions](#51-open-questions)
- 5.2 [Decision Log](#52-decision-log)
- 5.3 [Document Management Notes](#53-document-management-notes)
- 5.4 [Change History](#54-change-history)

---

# Part 1: Context

---

## 1.1 Problem Statement

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
Enterprise private-label prospects hit a ceiling.

---

## 1.2 User Personas

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

## 1.3 Current State

The `brand:` section in `config.defaults.yaml` (see Decision D6) exposes 9 fields.
The brand schema uses Zod `.nullish()` rather than `.default()` so that validation
and default resolution remain separate concerns (see Decision D3).

| Field                   | Type       | Default                     | ENV Override                  | Purpose                             |
| ----------------------- | ---------- | --------------------------- | ----------------------------- | ----------------------------------- |
| `primary_color`         | hex string | `#dc4a22`                   | `BRAND_PRIMARY_COLOR`         | Generates 44-shade oklch palette    |
| `product_name`          | string     | `Onetime Secret`            | `BRAND_PRODUCT_NAME`          | Displayed in UI, emails, TOTP       |
| `corner_style`          | enum       | `rounded`                   | `BRAND_CORNER_STYLE`          | `rounded` / `square` / `pill`       |
| `font_family`           | enum       | `serif`                     | `BRAND_FONT_FAMILY`           | `sans` / `serif` / `mono`           |
| `button_text_light`     | boolean    | `true`                      | `BRAND_BUTTON_TEXT_LIGHT`     | Light or dark text on brand buttons |
| `support_email`         | string     | `support@onetimesecret.com` | `BRAND_SUPPORT_EMAIL`         | Contact email in UI and emails      |
| `product_domain`        | string     | —                           | `BRAND_PRODUCT_DOMAIN`        | Canonical domain for the product    |
| `allow_public_homepage` | boolean    | `true`                      | `BRAND_ALLOW_PUBLIC_HOMEPAGE` | Show public landing page            |
| `allow_public_api`      | boolean    | `true`                      | `BRAND_ALLOW_PUBLIC_API`      | Expose public API                   |

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

## 1.4 Dogfood Readiness Assessment

See [brand-dogfood-gaps-ticket.md](brand-dogfood-gaps-ticket.md).

---

## 1.5 Gap Analysis: Ring Model

### Layers of Brand Identity

The priority levels above (P0-P3) rank work by dogfood impact — what hurts operators most.
The ring model provides a complementary lens: **what kind of intervention each item requires**.
The rings describe concentric layers of brand identity, ordered by distance from core:

```
┌─────────────────────────────────────────────┐
│           Ring 3: Contextual Identity       │
│  ┌───────────────────────────────────────┐  │
│  │       Ring 2: Visual Identity         │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │    Ring 1: Text Identity        │  │  │
│  │  │                                 │  │  │
│  │  │  Product name, support email,   │  │  │
│  │  │  TOTP issuer, error messages    │  │  │
│  │  └─────────────────────────────────┘  │  │
│  │                                       │  │
│  │  Logo, favicon, fonts, color config,  │  │
│  │  corner style, theme-color meta       │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  PWA manifest, og:image, "Powered by",      │
│  per-org branding, email sender domain,     │
│  terms/privacy URLs, GitHub/docs links      │
└─────────────────────────────────────────────┘
```

**Ring 1 — Text Identity**: The innermost layer. If you grep rendered output, does the
wrong brand name appear? Work here is mechanical — string replacements and fallback chain
fixes. Low complexity, high item count.

**Ring 2 — Visual Identity**: The next layer out. Does the product _look_ like someone
else's? Logo, favicon, fonts, color pipeline. Work here requires config plumbing and
asset management. Medium complexity.

**Ring 3 — Contextual Identity**: The outermost layer. Does the product _behave_ like
someone else's in surrounding contexts — browser chrome, app stores, social previews,
legal pages, third-party integrations? Work here touches new subsystems and external
surfaces. Highest architectural surface area.

The ring tells you the _shape_ of the work. Priority tells you the _urgency_. An item
can be Ring 1 (text fix) but P1 (not a dogfood blocker), or Ring 3 (new subsystem) but
P0 (operators hit it immediately). Both framings are useful for planning.

| Ring   | Description         | Nature of Work                            | Items                |
| ------ | ------------------- | ----------------------------------------- | -------------------- |
| Ring 1 | Text Identity       | Grep-and-replace, fallback neutralization | ~11 fallback strings |
| Ring 2 | Visual Identity     | Config wiring, asset pipelines            | 9 features           |
| Ring 3 | Contextual Identity | New subsystems, external integrations     | 14+ items            |

---

# Part 2: Architecture

---

## 2.1 Core Architecture

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

Product name flows through standard `t()` i18n with an explicit `{ product_name }`
parameter rather than a custom composable (see Decision D5).

### Key Design Decision: Shared Mechanism

Both lifecycle paths resolve through the same CSS custom property layer.
Tailwind v4's theme system is CSS-native — the `@theme` block in `style.css` defines
build-time color defaults as CSS custom properties, and `useBrandTheme` overrides those
same `--color-brand-*` variables at runtime. (The project retains `tailwind.config.ts` for
content paths, plugin registration, and font family declarations — but all brand color
definitions live in the CSS `@theme` block, not in JS config (see Decision D4).) Tailwind v4's cascade layers
(`@layer base`, `@layer components`, etc.) provide a clear specificity hierarchy, though
brand overrides themselves operate via inline styles on `:root` set by `useBrandTheme`,
which take precedence over all layer-scoped declarations by design.

This is architecturally rare. Most OSS SaaS projects (Mattermost, Chatwoot) bolt
per-tenant theming on as a separate system from install-level branding, creating
maintenance burden and feature asymmetry. OTS's unified approach means every new brand
config field automatically works at both levels.

### Key Files

| File                                                  | Role                                                     |
| ----------------------------------------------------- | -------------------------------------------------------- |
| `src/utils/brand-palette.ts`                          | oklch palette generator — 44 CSS vars from 1 hex         |
| `src/shared/composables/useBrandTheme.ts`             | Watches identityStore, injects/removes CSS vars on :root |
| `src/shared/constants/brand.ts`                       | Frontend defaults and neutral brand constants            |
| `src/shared/stores/identityStore.ts`                  | Holds current domain's brand settings                    |
| `src/shared/stores/bootstrapStore.ts`                 | Holds installation-level brand config                    |
| `src/assets/style.css`                                | `@theme` block — build-time Tailwind defaults            |
| `etc/defaults/config.defaults.yaml`                   | Backend brand config with ENV overrides                  |
| `lib/onetime/models/custom_domain/brand_settings.rb`  | Per-domain brand in Redis                                |
| `lib/onetime/mail/views/base.rb`                      | Email template brand helpers                             |
| `apps/web/core/views/helpers/initialize_view_vars.rb` | View bootstrapper                                        |

---

## 2.2 Design Token Architecture

### Current: Numbered Shades

The palette generator uses the oklch color space (see Decision D1) and produces 4
palette variants from a single hex input (see Decision D2).

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
- `brandcompdim-*` — dimmed complementary

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

#### Implementation: Core Semantic Aliases

Three aliases form the minimum viable semantic layer:

| Alias             | Light Theme Mapping      | Purpose                                                  |
| ----------------- | ------------------------ | -------------------------------------------------------- |
| `--brand-surface` | `var(--color-brand-50)`  | Background for brand-tinted containers, cards, panels    |
| `--brand-solid`   | `var(--color-brand-500)` | Primary buttons, active indicators, solid brand elements |
| `--brand-text`    | `var(--color-brand-900)` | Text rendered on `--brand-surface` backgrounds           |

These would be defined in `useBrandTheme` alongside the numbered palette variables. Components
would migrate from `bg-brand-50` to `bg-brand-surface`, decoupling usage intent from specific
shade numbers.

#### Dark Theme Remapping

The same semantic aliases enable dark theme auto-generation without additional config. In dark
mode, the alias mappings shift:

```
Light:  --brand-surface → var(--color-brand-50)   --brand-solid → var(--color-brand-500)  --brand-text → var(--color-brand-900)
Dark:   --brand-surface → var(--color-brand-950)  --brand-solid → var(--color-brand-400)   --brand-text → var(--color-brand-100)
```

The `branddim-*` palette already provides darker shade values. The semantic layer would select
from either the `brand-*` or `branddim-*` palette based on the current color scheme, giving
operators a coherent dark theme from the same single primary color input.

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

### Design Token Tooling

The current token pipeline (hex input → `brand-palette.ts` → 44 CSS vars → `useBrandTheme`
→ `:root`) is self-contained. Two external tools are planned to extend the pipeline into
design tooling and runtime theme switching:

| Tool                 | Status      | Role in OTS                                                                                                                                                  |
| -------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Penpot**           | **Planned** | Open-source design tool with native W3C DTCG token support; self-hostable. Maintains a shared design spec that stays in sync with the `--color-brand-*` vars |
| **TokiForge**        | **Planned** | Runtime token consumption with theme switching — handles dynamic remapping of the semantic alias layer beyond what `useBrandTheme` currently covers           |
| **Style Dictionary** | Future      | Cross-platform token transformation — generates iOS/Android equivalents from a shared token source. Relevant if native clients need the brand palette         |

Penpot and TokiForge are the next integration targets. Style Dictionary becomes relevant
only if tokens need to flow beyond CSS custom properties into native mobile platforms.

---

## 2.3 Dual-Lifecycle Model

### Install-Time vs Page-Load-Time

| Dimension                | Install-Time (Self-Hosted)                 | Page-Load-Time (Custom Domain)                 | Parity?                  |
| ------------------------ | ------------------------------------------ | ---------------------------------------------- | ------------------------ |
| Primary color            | ENV → config → bootstrap → CSS vars        | Redis → identityStore → CSS vars               | Yes                      |
| Product name             | ENV → config → bootstrap → i18n            | Redis → identityStore → i18n                   | Yes                      |
| Support email            | ENV → config → bootstrap                   | Redis → identityStore                          | Yes                      |
| Logo                     | **Not configurable**                       | Custom domain logo in MastHead                 | **No**                   |
| Corner style             | Config exists, **no runtime effect**       | Same gap                                       | Parity (broken)          |
| Font family              | Config exists, **Zilla Slab always loads** | Same gap                                       | Parity (broken)          |
| Email branding           | Logo hardcoded, color configurable         | No per-domain email logo                       | Parity                   |
| Theme extension          | Additional `@theme` properties via config  | Additional CSS custom properties via Redis     | Planned — same mechanism |
| Font file upload         | **Not configurable**                       | Not applicable — install-only feature          | Install-only             |
| Email sender name/domain | **Not configurable**                       | Not applicable — install-only feature          | Install-only             |
| Per-org branding         | **Not supported**                          | Not applicable — requires new resolution layer | N/A                      |

### What Mid-Tier SaaS Customers Should Get

Based on competitive analysis, a reasonable feature set for custom domain customers:

**Should have** (page-load-time, per-domain):

- Brand primary color (already working)
- Product name (already working)
- Logo URL (planned)
- Favicon color (planned)

**Install-only** (self-hosted operators):

- Font family
- Corner style
- Support email
- Terms/Privacy URLs
- "Powered by" toggle
- PWA manifest details
- Per-domain theme extension (additional CSS custom properties)

**Rationale**: Color, name, and logo are the core brand elements customers expect to
customize. Typography and layout details are installation-level decisions that affect
the entire product experience.

### Per-Organization Branding

Per-organization branding introduces a potential fourth resolution layer between
per-installation and per-domain. In a multi-tenant deployment, distinct organizations
within a single installation may require separate brand identities.

```
Per-Org Resolution (proposed):
  Layer 1: Per-Domain (Redis)          ← page-load-time
  Layer 1.5: Per-Organization (Redis)  ← org-scoped, page-load-time
  Layer 2: Per-Installation (ENV/config) ← install-time
  Layer 3: Hardcoded Fallback          ← compile-time
```

This differs from per-domain branding in scope: a single organization may span multiple
custom domains, or multiple organizations may share one installation without custom domains.
The brand resolution chain would check org membership before falling back to
installation defaults.

Key considerations:

- Organization identity must be determined from the authenticated session, not the URL
- Brand settings storage would extend `brand_settings.rb` with an org-scoped key prefix
- The existing `useBrandTheme` composable already watches reactive state, so org-level
  changes would propagate through the same CSS variable mechanism
- Interaction with per-domain branding needs a clear precedence rule (domain wins, org
  wins, or merge?)

### Performance: Runtime CSS Injection at Scale

CSS custom properties on `:root` are extremely fast — sub-millisecond for 44 variables.
The main concern is FOUC (Flash of Unstyled Content) when the composable applies vars
after Vue hydration.

**Mitigation**: Inject brand CSS in `<head>` as a `<style>` block during server-side
HTML generation, before Vue loads. The composable then becomes a no-op for the initial
paint and only activates on runtime changes (e.g., navigating between custom domains).

---

# Part 3: Cross-Cutting Concerns

---

## 3.1 Accessibility & Contrast

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
when the system needs to handle arbitrary typography.

---

## 3.2 Security Considerations

Brand customization introduces user-controlled inputs that render in HTML, CSS, email
templates, and PWA manifests. Each input is an attack surface.

### Input Validation Requirements

| Field                                | Threat                                                                                                                                    | Mitigation                                                                                                                                                            |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `primary_color`                      | CSS injection via malformed hex (e.g., `#fff; background: url(...)`)                                                                      | Strict hex regex: `/^#[0-9a-fA-F]{3,8}$/` — already validated by Zod schema                                                                                           |
| `product_name`                       | XSS in HTML contexts, email header injection                                                                                              | HTML-escape on render. Max length 100 chars. No newlines.                                                                                                             |
| `logo_url` (planned)                 | SSRF via `file://`, `data:`, internal IPs. Tracking pixels in emails.                                                                     | Scheme allowlist: `https://` only. No redirects. Validate reachable. Max size 2MB. CSP `img-src` directive.                                                           |
| `support_email`                      | Email header injection, phishing                                                                                                          | Validate email format. No newlines or special chars.                                                                                                                  |
| `font_family`                        | Enum — no injection risk                                                                                                                  | Already constrained to `sans`/`serif`/`mono`                                                                                                                          |
| `corner_style`                       | Enum — no injection risk                                                                                                                  | Already constrained to `rounded`/`square`/`pill`                                                                                                                      |
| Per-domain theme extension (planned) | Values flow through CSS custom properties, same as `primary_color`. Risk is limited to property values, not arbitrary selectors or rules. | Validate values with the same pipeline used for `primary_color` (strict format regex per property type). No raw CSS blocks — only named properties with typed values. |
| Font file upload (planned)           | Executable code in font files. License violations.                                                                                        | Format allowlist (woff2 only). Size limit (500KB). No server-side font parsing. Serve via CDN with `Content-Type: font/woff2`.                                        |
| PWA manifest (planned)               | XSS if `name`/`description` rendered in admin UI                                                                                          | JSON-encode all values. Never render manifest fields as raw HTML.                                                                                                     |
| Email sender name/domain (planned)   | SPF/DKIM/DMARC misconfiguration leading to email delivery failures or spoofing. Phishing via impersonated sender addresses.               | Validate domain ownership via DNS TXT record. Require SPF/DKIM alignment before enabling custom sender. Restrict to verified domains only. See Section 4.1.           |

### Content Security Policy (CSP) Implications

Adding configurable logos and fonts means CSP directives must be updated:

```
img-src 'self' https:;       ← allow external logo URLs (https only)
font-src 'self' https:;      ← allow external font URLs (when supported)
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

## 3.3 Quality Assurance: Linting & Visual Regression

### CSS Linting

The brand system's goal of eliminating hardcoded `#dc4a22` occurrences (Section 1.1) benefits
from automated enforcement. **Stylelint** can catch regressions at commit time:

- **Token naming conventions** — Custom rules to flag CSS values that should use
  `--color-brand-*` variables instead of raw hex (e.g., disallow `#dc4a22`, `#c43d1b`,
  or any hex matching the generated palette)
- **Variable usage patterns** — Enforce that brand-colored elements reference CSS custom
  properties, not Tailwind color utilities like `bg-orange-600`
- **Plugin architecture** — Extend with `stylelint-order` for property ordering or custom
  plugins for project-specific conventions

Recommended baseline config: `stylelint-config-standard` with project-specific overrides
for the `--color-brand-*` and `--color-brandcomp-*` namespaces.

### Visual Regression Testing

The brand system accepts arbitrary hex input from operators and custom domain owners. A color
that passes Zod validation can still produce a palette that breaks visual layouts (e.g., very
light primaries where brand-50 and brand-100 become indistinguishable from white backgrounds).
Visual regression testing catches these failures before they reach users.

| Tool           | Approach                                      | Fit                                                                                                     |
| -------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **Playwright** | Screenshot comparison with browser automation | Already in the stack (`pnpm run playwright`). Extend existing E2E suite with brand-variant screenshots. |
| **Lost Pixel** | Full-page and component-level visual testing  | Lower setup cost for component-level coverage without full E2E harness                                  |

**Recommended approach**: Extend the existing Playwright E2E suite to capture screenshots
under 3–4 representative brand colors (the default `#dc4a22`, a very light color, a very
dark color, and a cool-toned color). Compare against baselines on each PR that touches
`brand-palette.ts`, `useBrandTheme.ts`, or `style.css`.

For email templates (Section 4.1), Litmus and Email on Acid remain the right tools — visual
regression via Playwright does not cover email client rendering differences.

---

# Part 4: Implementation Specifics

---

## 4.1 Email Branding

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

### Custom Email Sender Name and Domain

Currently, all transactional emails (secret share notifications, verification, password
reset) are sent from the installation's default sender address. Operators cannot customize
the sender name or domain.

**Proposed config fields:**

| Field                 | Type   | Default               | ENV Override                | Purpose                           |
| --------------------- | ------ | --------------------- | --------------------------- | --------------------------------- |
| `email_sender_name`   | string | (product_name)        | `BRAND_EMAIL_SENDER_NAME`   | Display name in email From header |
| `email_sender_domain` | string | (installation domain) | `BRAND_EMAIL_SENDER_DOMAIN` | Domain portion of From address    |

**Requirements:**

- Sender domain must have valid SPF, DKIM, and DMARC records aligned with the sending
  infrastructure (see Section 3.2 for security implications)
- `email_sender_name` falls back to `brand.product_name` if not explicitly set
- Validation: domain ownership should be confirmed via DNS TXT record before activation
- This is an install-time-only feature — per-domain email sender customization introduces
  significant deliverability and abuse risks

---

## 4.2 Operator Documentation

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

---

# Part 5: Meta-Content

---

## 5.1 Open Questions


## 5.2 Decision Log

Decisions made during the brand system development. For significant architectural
decisions, create a formal ADR in `docs/architecture/decision-records/`.

| #   | Date    | Decision                                                   | Rationale                                                                                                         | ADR |
| --- | ------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --- |
| D1  | 2026-01 | Use oklch color space for palette generation               | Perceptually uniform, handles gamut clipping, modern browser support                                              | —   |
| D2  | 2026-01 | Generate 4 palettes from 1 hex (brand, comp, dim, dimcomp) | Covers light/dark and accent needs without additional config                                                      | —   |
| D3  | 2026-01 | Zod `.nullish()` not `.default()` for brand schema         | Schema validates format only; the store resolves defaults. This preserves the 3-layer fallback chain.             | —   |
| D4  | 2026-01 | Remove `extend.colors` from `tailwind.config.ts`           | Tailwind v4 uses CSS-only `@theme`. Config colors were a v3 holdover causing dual-source confusion.               | —   |
| D5  | 2026-01 | Replace `useBrandI18n` composable with standard `t()`      | Standard i18n with explicit `{ product_name }` parameter is simpler and more consistent than a custom composable. | —   |
| D6  | 2026-02 | Rename config key from `branding:` to `brand:`             | Shorter, consistent with other config section naming (site:, redis:, etc.)                                        | —   |

We will move this content to a single, focus ADR file once the system is stable and the major decisions are finalized. For now, this log captures the evolving decision landscape during development.

---

## 5.3 Document Management Notes

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
- **No living metrics** — Success metrics (adoption counts, hardcoded-value counts) go
  stale. Consider a script that counts `brand-*` class usage vs hardcoded colors and
  outputs a freshness report.

### Suggested Complementary Tools

| Tool                                              | Purpose                                                                           | When to Use                          |
| ------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------ |
| **Penpot**                                        | Shared design spec with W3C DTCG tokens synced to `--color-brand-*` vars          | Design ↔ code sync                   |
| **TokiForge**                                     | Runtime token consumption and theme switching for semantic alias remapping         | Semantic alias layer, dark theme     |
| GitHub Issues                                     | Task tracking for brand system work items                                         | Ongoing                              |
| Storybook                                         | Visual component library with brand variants                                      | When component coverage warrants it  |
| ADR files (`docs/architecture/decision-records/`) | Record key decisions from Open Questions                                          | As questions are resolved            |
| `brand-audit.sh` script                           | Automated count of hardcoded values                                               | Run before each release              |
| Stylelint                                         | Enforce token naming conventions, catch hardcoded hex values (see Section 3.3)    | On commit / in CI                    |
| Playwright visual regression                      | Screenshot baselines across brand color variants (see Section 3.3)                | On PRs touching brand pipeline files |

### CI/CD Pipeline for Brand Integrity

The `brand-audit.sh` script is a starting point. A full CI gate for brand system integrity
follows this pipeline pattern:

1. **Lint CSS on commit** — Stylelint catches hardcoded colors and naming violations
2. **Visual regression against brand configurations** — Playwright screenshots under
   3–4 representative colors, compared against baselines
3. **Token schema validation** — Verify that `brand-palette.ts` output matches the
   expected 44-variable schema (11 shades × 4 palettes)
4. **Block deployment on failure** — Any of the above failing prevents merge

This runs alongside existing checks (`pnpm run lint`, `pnpm run type-check`,
`pnpm run test:all:clean`). The brand-specific steps add coverage for the CSS variable
pipeline that TypeScript and unit tests do not reach.

### Keeping This Document Fresh

1. **After competitive research**: Update Section 1.5 with new findings.
2. **After resolving an Open Question**: Move it to Section 5.2 (Decision Log) with the
   resolution.
3. **Quarterly**: Re-run the automated audit (grep for hardcoded values) and update
   Section 1.4 counts.

---

## 5.4 Change History

| Version | Date       | Author              | Changes                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------- | ---------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1.0     | 2026-02-08 | Product/Engineering | Initial document from 4-agent dogfood audit                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| 1.1     | 2026-02-08 | Product/Engineering | Added security section (11), operator docs (13). Fixed palette count, font_family gap, open question ownership. Fresh-eyes review feedback.                                                                                                                                                                                                                                                                                                                                    |
| 1.2     | 2026-02-08 | Product/Engineering | Added 7 planned features: login page customization, per-domain theme extension, semantic color aliases, dark theme auto-generation, per-org branding, custom email sender, font file upload. Reframed custom CSS as Tailwind v4 theme extension. Expanded Sections 5, 6, 7, 8, 9, 11, 12, 14.                                                                                                                                                                                  |
| 1.3     | 2026-02-08 | Product/Engineering | Fact-check pass against Tailwind v4 capabilities reference. Corrected "100% CSS" claim to scope it to theme definitions (Section 3). Fixed `branddimcomp-*` palette prefix to `brandcompdim-*` (Section 7). Added design token tooling subsection (Section 7). Added Section 11: CSS linting (Stylelint) and visual regression testing (Playwright, Lost Pixel). Expanded Section 15 with CI/CD pipeline pattern for brand integrity. Renumbered sections sequentially (1–17). |
| 1.4     | 2026-02-08 | Product/Engineering | Restructured into five-part layout: Context, Architecture, Cross-Cutting Concerns, Implementation Specifics, Meta-Content. Nested Design Token Architecture and Dual-Lifecycle Model under Architecture. Added Decision Log cross-references (D1–D6). No content rewritten.                                                                                                                                                                                                    |

---

## References

- PR #2483: [Centralize brand customization system](https://github.com/onetimesecret/onetimesecret/pull/2483)
- Branch: `feature/brand-customization-system` (19 commits)
- Serena memory: `branding-centralization-architecture`
- Design system guide: `style.css` @theme block
- Email templates: `lib/onetime/mail/views/`
- Tailwind v4 capabilities reference: `docs/product/tailwind-v4-capabilities.md`
