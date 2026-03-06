> Part of the [Brand Customization System](brand-customization-system.md) product bible.

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
→ `:root`) is self-contained. One external design tool is planned, and one token library
was evaluated and found to be less capable than the in-house pipeline:

| Tool                 | Status                                        | Role in OTS                                                                                                                                                                           |
| -------------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Penpot**           | **Planned**                                   | Open-source design tool with native W3C DTCG token support; self-hostable. Maintains a shared design spec that stays in sync with the `--color-brand-*` vars                          |
| **TokiForge**        | **Evaluated — not adopted ([D7](brand-part5-meta.md#52-decision-log))** | Evaluated for semantic alias remapping and WCAG checking. Lacks oklch, functional Tailwind v4 support, and ecosystem maturity. The in-house pipeline is more capable for OTS's needs. |
| **Style Dictionary** | Future                                        | Cross-platform token transformation — generates iOS/Android equivalents from a shared token source. Relevant if native clients need the brand palette                                 |

Penpot is the next integration target for design-to-code token sync. Style Dictionary or
Cobalt UI become relevant if tokens need to flow beyond CSS custom properties into native
mobile platforms or if the semantic alias layer outgrows in-house maintenance.

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
