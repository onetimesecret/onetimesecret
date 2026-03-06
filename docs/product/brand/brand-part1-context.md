> Part of the [Brand Customization System](brand-customization-system.md) product bible.

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
