# docs/landscape/branding-and-theming-analysis.md
---

# OTS Branding & Theming: Landscape Brief

**Date**: February 8, 2026
**Scope**: private-label branding and theming capabilities across open-source self-hosted products
**Projects surveyed**: GitLab, Mattermost, Cal.com, Chatwoot, Documenso, Plausible Analytics

---

## Tech Stack Comparison

| | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| **Backend** | Ruby (custom) | Ruby on Rails | Go | Node.js / Next.js | Ruby on Rails | TypeScript | Elixir / Phoenix |
| **Frontend** | Vue.js | Vue.js | React | React (Next.js) | Vue.js 3 | React (React Router + Vite) | Phoenix LiveView |
| **CSS framework** | Tailwind v4 | Tailwind + SCSS | SCSS + CSS vars | Tailwind | SCSS + Bourbon | Tailwind + shadcn/ui | Tailwind |
| **Database** | Redis | PostgreSQL | PostgreSQL | PostgreSQL (Prisma) | PostgreSQL | PostgreSQL (Prisma) | PostgreSQL + ClickHouse |
| **ORM / data layer** | Custom | ActiveRecord | Custom Go | Prisma + tRPC | ActiveRecord | Prisma + tRPC + ts-rest | Ecto |
| **Job queue** | (in-process) | Sidekiq + Redis | Go goroutines | Inngest | Sidekiq + Redis | Inngest | Oban (Elixir) |
| **Design system** | None (manual) | Pajamas (@gitlab/ui) | Compass (deprecated) | Cal Atoms + Radix | BEM conventions | shadcn/ui + Figma system | None (Tailwind direct) |
| **Component library** | None | ~100 Vue components | mattermost-ui-library | Radix UI primitives | Custom Vue components | shadcn/ui (copy-paste) | None |
| **Build tooling** | Vite | Webpack | Webpack | Turborepo + Vite | Vite | Turborepo + Vite | Mix (Elixir) |
| **Monorepo** | No | No (single repo) | Yes (Go modules) | Yes (Turborepo) | No | Yes (Turborepo) | No |

### Observations on stack choices

Five of seven projects use Tailwind CSS for styling. OTS is the only one on Tailwind v4, which matters because v4's `@theme` directive enables CSS-first configuration of design tokens without a `tailwind.config.js` file. This architectural choice is why OTS can expose theme extension points that other projects in this set do not.

The Ruby/Rails projects (GitLab, Chatwoot) and the TypeScript/Prisma projects (Cal.com, Documenso) form two natural clusters. GitLab and Chatwoot share similar infrastructure patterns (Sidekiq, Redis, PostgreSQL). Cal.com and Documenso share nearly identical stacks (TypeScript, Prisma, tRPC, Turborepo). OTS sits outside both clusters: Ruby backend but not Rails, Redis as primary store rather than PostgreSQL.

Plausible is the outlier with Elixir/Phoenix and ClickHouse. Their Phoenix LiveView approach means server-rendered HTML with minimal client-side JavaScript, which constrains how much runtime theming they can offer.

---

## Branding Architecture Comparison

### How each project stores and applies branding

**GitLab**: Database-backed `appearances` table, exposed via REST API (`/api/v4/application/appearance`). Admin panel with file uploads for logos (nav bar, sign-in page, favicon) and text fields for titles/descriptions. Separate PWA manifest fields. Email branding is a boolean toggle (header/footer). Design token system (semantic CSS custom properties) handles color modes internally, but brand customization does not tap into it. The Appearance API covers chrome elements; it does not expose design token overrides.

**Mattermost**: Two separate systems. System-level branding (System Console > Customization) stores site name, brand image, and brand text in `config.json` or environment variables. User-level theming uses a JSON object with 24+ color tokens (sidebar, center channel, indicators, buttons) stored in per-user preferences. Enterprise tier adds per-team themes. The theme JSON is applied via CSS variables at runtime through a React ThemeProvider. This split means admin branding and user theming are architecturally decoupled.

**Cal.com**: Environment variables (`NEXT_PUBLIC_*`) for product name, support email, company name, and URLs. Logo changes require modifying files in `/web/public/` and constants in `/packages/lib/constants.ts`, then restarting. Color customization for public booking pages available via plan tier: basic plan gets brand color, team plan gets "remove Cal.com branding," platform plan gets custom CSS. Internally uses CSS custom properties (`--cal-bg`, `--cal-brand`, etc.) with light/dark variants, but these are not exposed as admin-configurable tokens. private-labeling is plan-gated, not architecturally enabled.

**Chatwoot**: Edition-gated private-labeling. Community edition requires source code modification. Enterprise edition exposes Super Admin settings at `/super_admin/settings` with `installation_configs` database table. Account-level settings allow name, language, widget positioning, and color palette selection. Widget customization is the most developed surface: a no-code builder for content, colors, positioning, and greeting messages. Custom CSS injection is supported for the widget but has documented limitations. Logo changes (3 variants: default, dark, monochrome) require source modification in community edition.

**Documenso**: Organization-level Prisma schema (`OrganisationGlobalSettings`) stores `brandingEnabled`, `brandingLogo`, `brandingUrl`, `brandingCompanyDetails`. Team-level settings (`TeamGlobalSettings`) can override organization defaults with nullable fields (null = inherit). Email branding includes custom sender domains with DKIM validation (`EmailDomain` model with public/private key pairs). Embedded signing flows expose CSS custom properties (`--documenso-primary-color`, `--documenso-accent-color`, `--documenso-border-radius`, `--documenso-text-color`). Per-org branding is a first-class database construct.

**Plausible**: Minimal branding surface. Embed dashboards support `theme=light|dark|system`, `background=transparent|{color}`, and `width=manual` URL parameters. Custom CSS can target semantic classes in the iframe. No logo, favicon, or product name customization. The Stats API (v2) enables building a fully custom dashboard, which is the intended path for deep private-labeling. private-label is really "build your own UI on our API."

### Architectural patterns

Three distinct patterns emerge:

1. **Admin panel + database** (GitLab, Chatwoot, Documenso): Branding stored in database rows, exposed through admin UI or API. Changes apply at runtime. The most mature approach for multi-tenant SaaS.

2. **Environment variables + restart** (Cal.com, Mattermost system-level): Configuration baked into the deployment. Changes require restart or rebuild. Works for single-tenant self-hosting but awkward for SaaS.

3. **CSS custom properties at render time** (OTS, Mattermost user-level, Documenso embeds): Theme computed and injected per request or per page load. The most flexible for runtime variation but requires the CSS architecture to support it.

OTS uses pattern 3 exclusively. The interesting finding is that no surveyed project combines all three: an admin UI for managing brand assets (pattern 1), environment-variable fallbacks for self-hosters (pattern 2), and CSS custom property generation from a single source color (pattern 3). That gap is where OTS's architecture could be extended.

---

## Feature Comparison: Detailed Ratings

Rating scale: **Strong** (market-leading), **Adequate** (functional), **Weak** (exists but limited), **Absent** (not available)

### Color & Palette

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| Color input simplicity | Strong (1 hex) | Adequate (2 colors) | Weak (20+ tokens) | Adequate (brand color) | Adequate (palette picker) | Adequate (primary + accent) | Weak (light/dark only) |
| Palette generation | Strong (44 oklch shades) | Absent | Absent | Absent | Absent | Absent | Absent |
| Dark mode | Strong (auto from same input) | Adequate (separate stylesheet) | Adequate (preset + custom) | Adequate (CSS var toggle) | Weak (LOGO_DARK only) | Absent | Adequate (embed param) |
| Runtime application | Strong (CSS vars, no reload) | Strong (CSS vars) | Adequate (ThemeProvider) | Weak (build-time) | Adequate (DB-backed) | Adequate (DB-backed) | Weak (iframe reload) |

### Brand Identity

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| Logo upload | Absent | Strong (3 slots + API) | Adequate (1 brand image) | Weak (file replacement) | Adequate (3 variants, enterprise) | Adequate (org settings) | Absent |
| Favicon | Absent | Strong (admin + API) | Absent | Weak (file replacement) | Absent | Absent | Absent |
| Product name | Adequate (config) | Strong (admin + API) | Adequate (30 char limit) | Adequate (env var) | Adequate (account setting) | Absent | Absent |
| PWA manifest | Absent | Strong (name, icon, desc) | Absent | Absent | Absent | Absent | Absent |

### Email Branding

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| Email colors | Adequate (brand_color) | Adequate (toggle on/off) | Strong (full HTML edit) | Absent | Absent | Adequate (JSON config) | N/A |
| Email logo | Absent | Adequate (via toggle) | Adequate (in HTML) | Absent | Absent | Adequate (org logo) | N/A |
| Custom sender domain | Absent | Strong | Absent | Absent | Absent | Strong (DKIM validated) | N/A |
| Reply-to customization | Absent | Absent | Absent | Absent | Absent | Strong (per-org) | N/A |

### Admin Experience

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| Admin UI for branding | Absent | Strong (panel + API) | Adequate (System Console) | Absent | Adequate (Super Admin, enterprise) | Adequate (org settings) | N/A |
| Preview before apply | Absent | Absent | Absent | Absent | Absent | Absent | Absent |
| API for branding | Absent | Strong (full CRUD) | Adequate (config API) | Absent | Weak (DB direct) | Adequate (tRPC) | Absent |
| Per-tenant branding | Absent | Absent (install-only) | Absent | Absent | Absent | Strong (per-org + per-team) | N/A |

### Theme Extensibility

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|---|
| CSS var architecture | Strong | Strong (semantic tokens) | Adequate (migrating) | Adequate | Weak (partial) | Adequate (embed vars) | Weak |
| Theme extension mechanism | Strong (Tailwind v4 @theme) | Absent | Absent | Absent | Absent | Absent | Absent |
| Font configuration | Adequate | Weak (nav only) | Absent | Absent | Absent | Absent | Absent |
| Corner radius control | Weak (broken) | Absent | Absent | Absent | Absent | Absent | Absent |
| Button text contrast | Adequate | Absent | Adequate (buttonColor) | Absent | Absent | Absent | Absent |

---

## Positioning Analysis

### How each product frames customization

**GitLab**: Positions branding as an enterprise administration feature. The Appearance admin panel is part of the "instance administration" surface. Messaging: "Make GitLab your own." Target: IT administrators deploying GitLab for their organization. The API availability signals that branding is a first-class managed object, not an afterthought.

**Mattermost**: Splits positioning between "admin branding" (System Console) and "user personalization" (theme picker). Admin branding is framed as corporate deployment configuration. User theming is framed as personal preference. The 24-token JSON theme system is positioned for power users and community theme sharing. Messaging: "Custom Branding Tools" in admin docs, "Customize Your Theme" in user docs.

**Cal.com**: Positions private-labeling as a paid feature tier. The product itself is "scheduling infrastructure" and branding is a platform play: if you build on Cal.com's platform, you can remove their brand and apply yours. This is monetization-oriented positioning. The actual technical implementation is thin (env vars, file replacement) but the commercial framing is sophisticated.

**Chatwoot**: Positions branding as an enterprise edition feature. Community edition gets the product, enterprise gets the polish. The widget customization is the most user-facing branding surface and gets the most attention. Positioning: open-source customer engagement with paid private-labeling.

**Documenso**: Positions branding as part of their organization/team hierarchy. Per-org branding with team overrides is the most architecturally mature multi-tenant approach in this set. Framing: "Organizations: The Foundation of Enterprise." Email domain verification with DKIM shows they're thinking about professional sender reputation, not just cosmetics.

**Plausible**: Does not position branding as a feature. Instead positions the Stats API as the path to custom dashboards. "private-label web analytics" marketing page exists but directs to the API. Framing: we give you the data engine, you build the UI.

### Unoccupied positioning space

No product in this set positions single-source palette generation as a feature. The closest analogy is design tools (Figma, Coolors) rather than application platforms. OTS could articulate: "One color. Complete brand identity." That framing does not exist in the self-hosted application space.

---

## Strengths and Gaps

### Where OTS is furthest ahead

**Palette generation from a single input.** This is not just a convenience feature; it's an architectural decision that constrains complexity. Every other product in this set requires the operator to think about multiple color values, understand color relationships, or accept preset themes. OTS computes the entire system from one hex value using oklch color space. The technical sophistication (perceptual uniformity, lightness-based shade generation) is invisible to the operator but produces measurably better results than manual token entry.

**Shared install/runtime mechanism.** The same CSS custom properties serve both deployment-time configuration and page-load-time rendering. Most other projects have separate code paths: Mattermost has `config.json` for system branding and user preferences for themes. Chatwoot has `installation_configs` for global and account settings for per-tenant. GitLab has the `appearances` table for admin and design tokens for component theming. Having one mechanism reduces surface area for bugs and makes the system more predictable.

**Tailwind v4 @theme extensibility.** No other project in this set uses Tailwind v4. The `@theme` directive means custom themes can extend the design token system without forking source or editing config files. This is a forward-looking architectural advantage that becomes more valuable as the feature surface grows.

### Where OTS has the most ground to cover

**No logo support at all.** Five of six projects surveyed support at least one logo upload. GitLab supports three (nav, sign-in, favicon). Chatwoot supports three variants (default, dark, monochrome). OTS supports zero. For any operator whose brand identity centers on a mark or wordmark, this is a hard blocker for private-labeling. Logo support is table stakes for private-label deployment.

**No admin UI.** GitLab has a dedicated Appearance panel with API. Mattermost has System Console. Chatwoot has Super Admin. Documenso has org settings. OTS requires config file or environment variable editing. This means branding changes require deployment access, which excludes non-technical stakeholders and makes iteration slower. The absence of an admin UI also means no validation, no preview, and no audit trail for branding changes.

**No email branding with assets.** Five of six projects surveyed support a logo or significant customization in emails. Documenso supports custom sender domains with DKIM. GitLab supports custom sender domains. OTS has `brand_color` and `logo_alt` text. Email is often the first branded touchpoint with end users, and text-only branding reads as unfinished.

**No favicon or PWA manifest.** GitLab has both. These are low-effort, high-visibility brand identity elements. A custom favicon is the minimum expectation for any private-label deployment. Browser tabs and bookmarks displaying the wrong favicon break the private-label illusion immediately.

**Corner style is broken.** Having a feature that does not work is worse than not having it. It signals incomplete implementation and erodes confidence in the branding system overall.

---

## Opportunities

### Gaps no surveyed project fills

**Brand preview mode.** No surveyed project offers a preview of branding changes before applying them. GitLab's admin panel applies changes immediately. Mattermost's theme picker shows a sidebar preview but not a full-page preview. A preview mode that renders the complete UI with proposed brand changes before committing would be unique and compelling, especially for operators managing branding on behalf of clients.

**Auto-contrast computation.** OTS already has the oklch infrastructure to compute text color contrast automatically per shade. If text color selection were derived from lightness values rather than configured manually, it would eliminate the `button_text_light` configuration field entirely and prevent accessibility failures. No other project attempts this.

**Dark theme auto-generation from the same primary color.** The `branddim-*` palette is a partial implementation. A fully automated semantic alias remapping that produces a complete dark theme from the same input hex would be unique. Currently, GitLab generates a separate `application_dark.css` stylesheet. Mattermost requires separate theme JSON for dark mode. Cal.com maintains separate CSS variable blocks. Auto-generating both from one input would extend OTS's single-source advantage.

**Semantic color aliases.** GitLab's design token system uses semantic names (`--gl-text-subtle`, `--gl-bg-default`) that abstract away raw color values. OTS's palette generates shades but does not (based on the matrix data) map them to semantic roles like "surface," "on-surface," "primary-container," "on-primary-container." Adding a semantic layer would make the palette system more useful to theme extenders without requiring them to understand which shade number to use for which purpose.

### Gaps that are fillable with moderate effort

**Favicon support.** Serving a configurable favicon is straightforward. Accept an image upload or URL, serve it from the appropriate route. This closes a visible gap with minimal architectural change.

**Basic logo support.** Even a single logo slot (displayed in the header and emails) would move OTS from "absent" to "adequate" on the most-cited gap. File upload, storage, and rendering in the layout template.

**Email logo injection.** If logo support exists, inserting it into email templates is incremental. Combined with the existing `brand_color`, this moves email branding from "weak" to "adequate."

---

## Ecosystem Trends

### Ecosystem investment patterns

**GitLab's design token system is maturing.** Their migration from SCSS variables to semantic CSS custom properties is progressing methodically. If they expose design token overrides through the Appearance API (currently they don't), they would surpass every project in this set on theming depth. Their Pajamas design system with ~100 components means token changes would cascade consistently. The gap between "tokens exist internally" and "tokens are admin-configurable" is not large.

**Documenso's multi-tenant branding architecture is the most complete.** Organization-level settings with team-level overrides, custom email domains with DKIM, per-org sender addresses, and CSS variables for embedded flows. If OTS moves toward multi-tenant or managed-service scenarios, Documenso's schema is the reference implementation for how to structure branding data.

**Cal.com's commercial framing of private-labeling as a paid tier.** Even with thin technical implementation, Cal.com successfully monetizes branding through plan gating. This validates market demand for private-labeling features but also signals that the market may accept "remove our brand" as sufficient private-labeling for many use cases, potentially limiting the value of OTS's more technically sophisticated approach.

### Areas of exposure

**The broken corner style feature.** If the branding system's only unique UI-surface features (corner style, font config) are partially broken, the "advanced theming" positioning is undermined before it starts.

**Config-file-only administration.** As other projects add admin UIs and APIs for branding, the gap in operator experience widens. Technical users tolerate config files, but the trend across this set is toward UI-based brand management.

---

## Strategic Implications

### Where to differentiate vs. achieve parity

**Parity targets** (close the gap, match the market):

- Logo support (at least one slot): every serious private-label comparison starts here
- Favicon: low effort, high visibility
- Fix corner style: a broken feature is a negative signal
- Basic admin UI or API for branding: does not need to be GitLab-scale, but config-file-only is becoming an outlier

**Differentiation investments** (extend the advantage):

- Auto-contrast computation: makes the palette system smarter and removes a config field
- Dark theme auto-generation: extends the single-source-color advantage into the most-requested theming dimension
- Semantic color aliases: makes the palette system usable by theme extenders without shade-number expertise
- Brand preview mode: unique in the surveyed set, high perceived value

**Monitor but do not invest yet**:

- Per-org branding: only relevant if OTS moves toward multi-tenant SaaS
- Custom email sender domains: high effort (DKIM, SPF, DNS verification), niche demand for a secrets tool
- PWA manifest: GitLab is the only one doing this; unclear if the market cares

### Architecture observation

OTS's palette generation system is technically ahead of every other project in this set. The risk is that this advantage is invisible to operators who evaluate branding by checking boxes: "Can I upload a logo? Can I change the favicon? Is there an admin panel?" The palette system is sophisticated but does not produce the artifacts that operators expect in a private-label feature comparison.

The strategic question is sequencing: close the visible gaps first (logo, favicon, admin UI) so the branding system passes checkbox evaluation, then differentiate on the palette and theming features that no other project matches.

---

## Tool & Infrastructure Summary

For reference, the complete tool ecosystem each project uses:

| Category | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|
| **Language** | Ruby | Go | TypeScript | Ruby | TypeScript | Elixir |
| **Web framework** | Rails | Custom | Next.js (migrating to App Router) | Rails 7 | React Router + Vite (migrated off Next.js) | Phoenix |
| **JS framework** | Vue.js | React + Redux | React + React Query | Vue.js 3 + Vuex | React + tRPC React Query | Phoenix LiveView (minimal JS) |
| **CSS** | Tailwind + SCSS | SCSS + CSS vars | Tailwind | SCSS + Bourbon (BEM) | Tailwind + shadcn/ui | Tailwind |
| **Database** | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL + ClickHouse |
| **ORM** | ActiveRecord | Custom | Prisma | ActiveRecord | Prisma (+ Kysely) | Ecto |
| **Background jobs** | Sidekiq | Go goroutines | Inngest | Sidekiq | Inngest | Oban |
| **API style** | REST (Rails) | REST + WebSocket | tRPC (internal) + REST v2 (public) | REST (Rails) | tRPC (internal) + ts-rest (public) | REST |
| **Auth** | Devise (Rails) | Custom | NextAuth.js + SAML | Devise (Rails) | Custom + SAML | Custom (Phoenix) |
| **Monorepo tool** | None | Go modules | Turborepo | None | Turborepo | None |
| **Design system** | Pajamas | Compass (deprecated) | Cal Atoms + Radix | BEM conventions | shadcn/ui | None |
| **Charts/viz** | (internal) | (internal) | Recharts | Chart.js | None | Chart.js |
| **Email** | Rails mailers | Go SMTP | react-email + Nodemailer | Rails mailers | react-email + Nodemailer | Bamboo (Elixir) + Mailgun |
| **File storage** | Local + object storage | Local + S3 | S3 | ActiveStorage (S3/GCS/Azure) | S3 (pre-signed URLs) | N/A |
| **Error tracking** | Sentry | Sentry | Sentry | Sentry | Sentry | Sentry |
| **Analytics** | Snowplow | (none documented) | PostHog | (none documented) | PostHog | Self (dogfooding) |

Notable: Documenso's migration off Next.js to React Router + Vite (citing 45+ second HMR times and debugging pain with Server Actions) is a data point worth tracking. Cal.com remains on Next.js but migrated from Pages Router to App Router. Both use Turborepo for monorepo management. The TypeScript/Prisma/tRPC stack appears to be consolidating as a default for new open-source SaaS projects.

---

*Analysis date: February 8, 2026. Feature comparisons based on current public documentation and source code. Landscapes shift; verify specific claims before using in external-facing materials.*
