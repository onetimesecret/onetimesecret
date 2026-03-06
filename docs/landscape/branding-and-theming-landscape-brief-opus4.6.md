# OTS Branding & Theming: Landscape Brief

**Date**: February 8, 2026
**Scope**: Private-label branding and theming capabilities across open-source self-hosted products
**Projects surveyed**: GitLab, Mattermost, Cal.com, Chatwoot, Documenso, Plausible Analytics, Zitadel, Keycloak, Rallly, Outline

---

## 1. Tech Stack Comparison

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

### Expanded set

| | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|
| **Backend** | Go | Java (Quarkus) | TypeScript (Next.js) | TypeScript (Node.js) |
| **Frontend** | Angular | FreeMarker templates + Vanilla JS | React | React |
| **CSS framework** | Angular Material | Custom + PatternFly | Tailwind | Styled Components |
| **Database** | CockroachDB / PostgreSQL | PostgreSQL | PostgreSQL (Prisma) | PostgreSQL (Sequelize) |
| **Design system** | Angular Material | PatternFly (partial) | None | None |

### Stack observations

Five of seven original projects use Tailwind CSS for styling. OTS is the only one on Tailwind v4, which matters because v4's `@theme` directive enables CSS-first configuration of design tokens without a `tailwind.config.js` file. This architectural choice is why OTS can expose theme extension points that other projects in this set cannot.

The Ruby/Rails projects (GitLab, Chatwoot) and the TypeScript/Prisma projects (Cal.com, Documenso, Rallly) form two natural clusters. GitLab and Chatwoot share similar infrastructure patterns (Sidekiq, Redis, PostgreSQL). Cal.com and Documenso share nearly identical stacks (TypeScript, Prisma, tRPC, Turborepo). OTS sits outside both clusters: Ruby backend but not Rails, Redis as primary store rather than PostgreSQL.

The identity/auth projects (Zitadel, Keycloak) bring Go and Java respectively. Both have more elaborate theming systems than most application-layer projects, consistent with their role as trust-mediating surfaces where branding is a security signal, not a cosmetic one.

Plausible is the outlier with Elixir/Phoenix and ClickHouse. Their Phoenix LiveView approach means server-rendered HTML with minimal client-side JavaScript, which constrains how much runtime theming they can offer.

Documenso's migration off Next.js to React Router + Vite (citing 45+ second HMR times and debugging pain with Server Actions) is a data point worth tracking. Cal.com remains on Next.js but migrated from Pages Router to App Router. Both use Turborepo for monorepo management.

---

## 2. Branding Architecture Comparison

### How each project stores and applies branding

**GitLab**: Database-backed `appearances` table, exposed via REST API (`/api/v4/application/appearance`). Admin panel with file uploads for logos (nav bar, sign-in page, favicon) and text fields for titles/descriptions. Separate PWA manifest fields. Email branding is a boolean toggle (header/footer). Design token system (semantic CSS custom properties via Pajamas) handles color modes internally, but brand customization does not tap into it. The Appearance API covers chrome elements; it does not expose design token overrides. Active MRs adding design tokens to components (GlToggle, labels, text) and Figma sync exploration exist, but no public feature request for exposing design tokens via the Appearance API. The design token system is being built for internal consistency, not external customization.

**Mattermost**: Two separate systems. System-level branding (System Console > Customization) stores site name, brand image, and brand text in `config.json` or environment variables. User-level theming uses a JSON object with 24+ color tokens (sidebar, center channel, indicators, buttons) stored in per-user preferences. Enterprise tier adds per-team themes. The theme JSON is applied via CSS variables at runtime through a React ThemeProvider. This split means admin branding and user theming are architecturally decoupled. The specific `changeCSS()` migration (Issue #16028) was completed, replacing patterns like `changeOpacity(theme.sidebarBg, 0.3)` with `rgba(var(--sidebar-bg-rgb), 0.3)` and removing corresponding `changeCSS()` calls from `utils/utils.jsx`. The broader campaign's overall completion status is undocumented; inspecting the current codebase for remaining `changeCSS()` calls would reveal how much legacy theming code remains.

**Cal.com**: Environment variables (`NEXT_PUBLIC_*`) for product name, support email, company name, and URLs. Logo changes require modifying files in `/web/public/` and constants in `/packages/lib/constants.ts`, then restarting. Color customization for public booking pages available via plan tier: basic plan gets brand color, team plan gets "remove Cal.com branding," platform plan gets custom CSS. Internally uses CSS custom properties defined in `apps/web/styles/globals.css`:

```css
:root {
  --cal-bg-emphasis: #e5e7eb;
  --cal-bg: white;
  --cal-bg-subtle: #f3f4f6;
  --cal-bg-muted: #f9fafb;
  --cal-bg-inverted: #111827;
  --cal-bg-info: #dee9fc;
  --cal-bg-success: #e2fbe8;
  --cal-bg-attention: #fceed8;
  --cal-bg-error: #f9e3e2;
}
```

For self-hosted instances, modification targets `globals.css` directly; the documentation recommends creating new CSS files and importing them to reduce merge conflicts. For Platform plans, "Cal Atoms" (React components) accept styling props, but the exact CSS injection mechanism isn't documented publicly.

**Chatwoot**: Edition-gated private-labeling. Community edition requires source code modification for logo changes at `app/javascript/dashboard/assets/images/woot-logo.svg` and various favicon/icon files in `public/`. Community forks exist that automate private-labeling: `jspenst/chatwoot-private-label`, `bendogabriel/chatwoot-whitelabel`. Configuration approaches from forks include environment variables for `LOGO_THUMBNAIL`, `LOGO`, `LOGO_DARK`; database modification in `installation_configs` table; and asset override via zip archive with `extract_brand_assets.sh` script. Files that can be overridden include `android-icon-36x36.png`, `apple-icon-180x180.png`, `favicon-16x16.png`, `ms-icon-310x310.png`, and similar platform icons. Enterprise edition exposes Super Admin settings at `/super_admin/settings`. Account-level settings allow name, language, widget positioning, and color palette selection. Widget customization is the most developed surface: a no-code builder for content, colors, positioning, and greeting messages.

**Documenso**: Organization-level Prisma schema (`OrganisationGlobalSettings`) stores `brandingEnabled`, `brandingLogo`, `brandingUrl`, `brandingCompanyDetails`. The `brandingLogo` field stores a reference to an uploaded asset (not a URL or base64); the upload flow is through the admin UI navigating to Organisation/Team Settings > Branding tab. Team-level settings (`TeamGlobalSettings`) can override organization defaults with nullable fields (null = inherit). Email branding includes custom sender domains with DKIM validation (`EmailDomain` model with public/private key pairs). Embedded signing flows expose CSS custom properties (`--documenso-primary-color`, `--documenso-accent-color`, `--documenso-border-radius`, `--documenso-text-color`). Per-org branding is a first-class database construct.

**Plausible**: Minimal branding surface. Embed dashboards support `theme=light|dark|system`, `background=transparent|{color}`, and `width=manual` URL parameters. Custom CSS can target semantic classes in the iframe. No logo, favicon, or product name customization. The Stats API (v2) enables building a fully custom dashboard, which is the intended path for deep private-labeling. Open-source implementations using the Stats API include Prezly (powering analytics for customers including Shopify, Sennheiser), PayloadCMS dashboard analytics plugin, Laravel packages for Plausible API integration, and a Fivetran connector for data pipelines. No standalone open-source private-label dashboard project emerged from the search.

**Zitadel**: Branding configurable at two levels: instance-level (default for all users) and organization-level (per-org overrides via `is_default` boolean). Customization options include logo upload (separate for light/dark themes), icon upload, colors (background, primary for buttons/links/highlights, warn for errors, font color), and font upload (TTF files). Advanced options: hide loginname suffix, hide ZITADEL watermark. A preview window shows changes before activation via an "Apply configuration" button. The Management API provides full CRUD endpoints for branding settings, including a `GetPreviewLabelPolicy` endpoint for testing changes before committing. Branding applies to login UI and emails. The two-tier hierarchy (instance with org override) is the most trust-aware branding architecture in this set.

**Keycloak**: Extensive theming via FreeMarker templates organized by theme type (login, account, email). Themes use a `theme.properties` file specifying parent themes, imports, and CSS includes. Theme inheritance allows extending base themes and overriding specific files. The effort level ranges from low (CSS tweaks) to high (complex SPI providers). Key architectural detail: the inheritance model uses both `parent` (for template fallback) and `import` (for shared resources), which is a documented source of confusion. Theme deployment in Kubernetes requires volume mounts. Cache invalidation is a significant operational pain point (multiple cache layers, no hot reload, requires server restart).

**Rallly**: Private-labeling added in v4.6.0 (January 2026) as Enterprise add-on. Configuration via environment variables and a Control Panel UI. Customizable elements: instance name, primary colors for light and dark modes separately, logo slots (light/dark variants), and attribution removal toggle. Scope is simple and recent. Similar to OTS in product scope (simple tool, trust-sensitive context) and configuration approach (env vars + admin UI).

**Outline**: Workspace-level accent color and logo (Settings > Workspace > Details). Cloud-hosted custom domain add-on removes Outline branding from public content. "Powered by Outline" attribution removal requires the custom domain purchase. No font customization, no dark mode separate configuration, no advanced color palette. Limited to workspace level only with no per-organization branding for multi-tenant scenarios.

### Architectural patterns

Four distinct patterns emerge:

1. **Admin panel + database** (GitLab, Chatwoot Enterprise, Documenso, Zitadel, Outline): Branding stored in database rows, exposed through admin UI or API. Changes apply at runtime. The most mature approach for multi-tenant SaaS.

2. **Environment variables + restart** (Cal.com, Mattermost system-level, Rallly): Configuration baked into the deployment. Changes require restart or rebuild. Works for single-tenant self-hosting but awkward for SaaS.

3. **CSS custom properties at render time** (OTS, Mattermost user-level, Documenso embeds): Theme computed and injected per request or per page load. The most flexible for runtime variation but requires the CSS architecture to support it.

4. **Template override** (Keycloak, Chatwoot Community): Full control through file-system modifications to templates/assets. Maximum flexibility but creates upgrade friction and requires developer involvement for every change.

OTS uses pattern 3 exclusively. No surveyed project combines all three runtime patterns: an admin UI for managing brand assets (pattern 1), environment-variable fallbacks for self-hosters (pattern 2), and CSS custom property generation from a single source color (pattern 3). That gap is where OTS's architecture could be extended.

Zitadel is the closest to combining patterns 1 and 3: database-backed settings with API access, applied as runtime CSS. It lacks pattern 3's generative aspect (no palette computation from a single input) but has the most complete admin-to-render pipeline.

---

## 3. Feature Comparison: Detailed Ratings

Rating scale: **Deep** (comprehensive, well-developed), **Adequate** (functional), **Limited** (exists but constrained), **-** (not available)

### Color & Palette

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Color input simplicity | Deep (1 hex) | Adequate (2 colors) | Limited (20+ tokens) | Adequate (brand color) | Adequate (palette picker) | Adequate (primary + accent) | Limited (light/dark only) | Adequate (4 colors) | Limited (full CSS edit) | Adequate (primary per mode) | Limited (accent only) |
| Palette generation | Deep (44 oklch shades) | - | - | - | - | - | - | - | - | - | - |
| Dark mode | Deep (auto from same input) | Adequate (separate stylesheet) | Adequate (preset + custom) | Adequate (CSS var toggle) | Limited (LOGO_DARK only) | - | Adequate (embed param) | Deep (separate light/dark) | Adequate (per-theme) | Deep (separate per mode) | - |
| Runtime application | Deep (CSS vars, no reload) | Deep (CSS vars) | Adequate (ThemeProvider) | Limited (build-time) | Adequate (DB-backed) | Adequate (DB-backed) | Limited (iframe reload) | Deep (API + runtime) | Limited (restart for cache) | Adequate (env + UI) | Adequate (DB-backed) |

### Brand Identity

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Logo upload | - | Deep (3 slots + API) | Adequate (1 brand image) | Limited (file replacement) | Adequate (3 variants, enterprise) | Adequate (org settings) | - | Deep (light/dark + icon) | Deep (per-theme) | Adequate (light/dark) | Adequate (workspace) |
| Favicon | - | Deep (admin + API) | - | Limited (file replacement) | - | - | - | Deep (icon upload) | Adequate (per-theme) | - | - |
| Product name | Adequate (config) | Deep (admin + API) | Adequate (30 char limit) | Adequate (env var) | Adequate (account setting) | - | - | - | Adequate (realm display name) | Adequate (instance name) | Adequate (workspace name) |
| PWA manifest | - | Deep (name, icon, desc) | - | - | - | - | - | - | - | - | - |
| Attribution removal | - | - | - | Adequate (paid tier) | Adequate (enterprise) | - | - | Deep (watermark toggle) | - | Deep (toggle) | Adequate (custom domain) |

### Email Branding

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Email colors | Adequate (brand_color) | Adequate (toggle on/off) | Deep (full HTML edit) | - | - | Adequate (JSON config) | - | Adequate (brand colors) | Deep (FreeMarker) | - | - |
| Email logo | - | Adequate (via toggle) | Adequate (in HTML) | - | - | Adequate (org logo) | - | Adequate (org logo) | Deep (per-theme) | - | - |
| Custom sender domain | - | Deep | - | - | - | Deep (DKIM validated) | - | - | - | - | - |
| Reply-to customization | - | - | - | - | - | Deep (per-org) | - | - | - | - | - |

### Admin Experience

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Admin UI for branding | - | Deep (panel + API) | Adequate (System Console) | - | Adequate (Super Admin, enterprise) | Adequate (org settings) | - | Deep (console + API) | Limited (file editing) | Adequate (Control Panel) | Adequate (workspace settings) |
| Preview before apply | - | - | - | - | - | - | - | Deep (preview window) | - | - | - |
| API for branding | - | Deep (full CRUD) | Adequate (config API) | - | Limited (DB direct) | Adequate (tRPC) | - | Deep (Management API + v2) | - | - | - |
| Per-tenant branding | - | - (install-only) | - | - | - | Deep (per-org + per-team) | - | Deep (per-org) | Deep (per-realm) | - | - |

### Theme Extensibility

| Capability | OTS | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible | Zitadel | Keycloak | Rallly | Outline |
|---|---|---|---|---|---|---|---|---|---|---|---|
| CSS var architecture | Deep | Deep (semantic tokens) | Adequate (migrating) | Adequate | Limited (partial) | Adequate (embed vars) | Limited | - (Angular Material) | Limited (raw CSS) | Limited | Limited |
| Theme extension mechanism | Deep (Tailwind v4 @theme) | - | - | - | - | - | - | - | Adequate (inheritance) | - | - |
| Font configuration | Adequate | Limited (nav only) | - | - | - | - | - | Deep (TTF upload) | Adequate (per-theme) | - | - |
| Corner radius control | Limited (broken) | - | - | - | - | - | - | - | - | - | - |

---

## 4. Positioning Analysis

### How each project frames customization

**GitLab**: Positions branding as an enterprise administration feature. The Appearance admin panel is part of the "instance administration" surface. Messaging: "Make GitLab your own." Target: IT administrators deploying GitLab for their organization. The API availability signals branding as a first-class managed object.

**Mattermost**: Splits positioning between "admin branding" (System Console) and "user personalization" (theme picker). The 24-token JSON theme system is positioned for power users and community theme sharing. Messaging: "Custom Branding Tools" in admin docs, "Customize Your Theme" in user docs.

**Cal.com**: Positions private-labeling as a paid feature tier. Branding is a platform play: if you build on Cal.com's platform, you can remove their brand and apply yours. The actual technical implementation is thin (env vars, file replacement) but the commercial framing is sophisticated.

**Chatwoot**: Positions branding as an enterprise edition feature. Community edition gets the product, enterprise gets the polish. Widget customization is the most user-facing branding surface and gets the most attention.

**Documenso**: Positions branding as part of their organization/team hierarchy. Per-org branding with team overrides is the most architecturally mature multi-tenant approach among the application-layer projects. Framing: "Organizations: The Foundation of Enterprise." Email domain verification with DKIM shows they're thinking about professional sender reputation, not just cosmetics.

**Plausible**: Does not position branding as a feature. Instead positions the Stats API as the path to custom dashboards. "Private-label web analytics" marketing page exists but directs to the API. Framing: we give you the data engine, you build the UI.

**Zitadel**: Positions branding as a trust signal. Branding applies to login screens and emails, the surfaces where users make authentication decisions. The two-tier model (instance + org override) is framed around multi-tenancy for identity providers serving multiple organizations. Preview-before-apply is consistent with the "don't break trust surfaces" positioning.

**Keycloak**: Positions theming as developer infrastructure. Full template control via FreeMarker is framed as "extensibility" rather than "branding." The audience is developers building identity solutions, not administrators configuring them. Theme-per-realm supports multi-tenant identity but requires developer effort per tenant.

**Rallly**: Positions private-labeling as an enterprise add-on for self-hosted instances. Simple scope: name, colors, logos, attribution toggle. Framing targets organizations embedding Rallly as internal tooling.

**Outline**: Positions branding minimally. Accent color and logo are workspace settings, not a featured capability. Attribution removal is gated behind custom domains (a paid add-on for cloud, a configuration step for self-hosted).

**Coolify** (PaaS): No official branding feature in Coolify's documentation or changelog. A community fork adding private-label branding exists, suggesting demand, but the feature isn't upstream. Included here as a data point: even infrastructure-layer projects face private-labeling requests.

### Unoccupied positioning space

No product in this set positions single-source palette generation as a feature. The closest analogy is design tools (Figma, Coolors) rather than application platforms. No open-source project was found that generates full design system palettes from a single hex input using oklch. OTS's approach appears novel in the self-hosted space. The framing "one color, complete brand identity" does not exist in the self-hosted application space.

---

## 5. Operator Experience Patterns

Mined from GitHub issues, discussions, and forums. These patterns reveal what operators actually encounter when attempting to private-label self-hosted products.

### Chatwoot

Recurring pain points around brand removal:

- "How do I change the logo and installation name?" is a recurring question in community discussions.
- Database modification workaround (`installation_configs` table) is non-obvious and undocumented in primary docs.
- Community Edition vs Enterprise confusion: operators expect branding to be a basic feature, not an edition-gated one.
- Cloudron users hit read-only filesystem issues that prevent source modification.
- **Issue #13306** (open): "Chatwoot AI" tooltip in label suggestions cannot be configured, forcing private-label resellers to fork the frontend.
- **Issue #13466** (open, Feb 2026): WhatsApp integration shows "Reply from Chatwoot," breaking private-label deployments.
- **Issue #1211** (open, 5+ years): Cannot set brand icon as agent avatar for multi-brand environments.
- Community forks (`jspenst/chatwoot-private-label`, `bendogabriel/chatwoot-whitelabel`) exist specifically because the official private-labeling path is too difficult.

### Keycloak

Theme system power comes with significant operational friction:

- **Issue #23503** (open, 8 upvotes): No way to clear template cache without restarting the server. Multiple cache layers (FreeMarkerUtil volatile map, FreeMarker TemplateCache, theme structure map, kc-gzip-cache directory) all require restart. Deleting `data/tmp/kc-gzip-cache` only clears static resources, not templates.
- **Issue #10946** (open, 18 upvotes): No theme versioning mechanism. Browser caches indefinitely; operators must manually bust caches on theme updates.
- **Issue #46100** (open): Database queries on every login page load despite local Infinispan cache configured.
- Theme inheritance confusion: `parent` (template fallback) vs `import` (shared resources) serve different purposes but the distinction is not well-documented.
- Version upgrades break custom themes. Bundled themes receive updates; custom overrides don't automatically inherit fixes. No automatic compatibility detection.
- Kubernetes deployment of custom themes requires volume mounts, adding deployment complexity.
- Development requires disabling caching (`--spi-theme-cache-themes=false --spi-theme-cache-templates=false`) which measurably degrades performance. No middle ground between "no caching" and "restart to see changes."

### GitLab

- Design tokens not exposed for customization through the Appearance API. The Pajamas design system builds tokens for internal consistency, not external override.
- Appearance API limited to logos, text, and basic chrome. No color token access.
- Dark mode adaptation requires internal token work; no operator-facing dark mode branding controls.

### Mattermost

- **Issue #27372**: Custom branding overlaps with back button on signin pages (layout collision).
- **Issue #11067** (5-year-old bug, resolved recently): Custom branding text/images invisible on mobile.
- **Issue #15929** (open): Cannot render custom emoji in branding text.
- **PR #27040** (merged Jan 2026): Active development on branding features continues.

### Plausible

- Stats API requires development effort for custom dashboards. No ready-made private-label dashboard project exists.
- Embed approach limits customization to theme and background color.
- Privacy-first positioning, not private-label-first. Minimal community private-label requests.

### Cross-project themes

1. **Documentation gaps**: Branding docs are often incomplete or outdated across projects. Operators discover configuration approaches from forum posts and community forks rather than official documentation.
2. **Fork maintenance burden**: Source code modifications create upgrade friction. Every project that requires file modification for branding (Chatwoot Community, Cal.com, Keycloak) generates community forks, and those forks drift from upstream.
3. **Light/dark mode**: Products that don't handle both modes create operator work. Separate configuration for light and dark is becoming expected; only Zitadel and Rallly handle this cleanly.
4. **Email branding**: Often overlooked or requires separate configuration. Email is frequently the first branded touchpoint with end users, yet it's the least developed branding surface across the set.
5. **Mobile rendering**: Rarely documented, frequently broken. Mattermost's 5-year mobile branding bug illustrates how mobile branding is treated as secondary.
6. **Hardcoded brand references**: Chatwoot's "Chatwoot AI" tooltip and "Reply from Chatwoot" in WhatsApp demonstrate how brand references leak into unexpected surfaces. These are the hardest to find and the most damaging to private-label credibility.
7. **Cache management**: Keycloak's multi-layer cache problem illustrates what happens when theming interacts with production infrastructure. Any project offering runtime theming will eventually face cache invalidation as an operational concern.

---

## 6. Design Token Architecture Deep Dive

### GitLab / Pajamas

Token count: estimated 200-400 total. The directory shows 50+ action tokens alone.

Naming convention: `[group].[component].[property].[state]`. Example: `action.confirm.background.color.hover`.

Token hierarchy (three tiers):
1. **Constant**: Raw values (`color.purple.100`)
2. **Semantic**: Design decisions referencing constants (`status.brand.background.color`)
3. **Contextual**: Component-specific, referencing semantic or constant tokens (`avatar.fallback.background.purple`)

Output formats: Figma variables, CSS custom properties (`var(--gl-*)`), SCSS variables (`$gl-*`).

Responsive handling: Not token-based; handled at component level.

Versioning: Tokens are part of GitLab UI releases; breaking changes documented in changelogs.

Current state: Active MRs adding design tokens to components (GlToggle, labels, text). Figma sync exploration for design tokens underway. The system is maturing but remains internal-facing.

### Cal.com

Token approach: CSS custom properties in `globals.css`. Flat namespace with semantic naming (`--cal-bg-emphasis`, `--cal-bg-error`).

Token count: approximately 30-50 color tokens based on documentation samples.

Architecture: Simpler than GitLab. No hierarchy. Light/dark mode via `.dark` class override.

Design tokens documented at design.cal.com.

### Documenso (shadcn-based)

Token approach: Uses shadcn/ui conventions. CSS custom properties following shadcn patterns: `--background`, `--foreground`, `--primary`, `--secondary`, etc. HSL-based color values. Tailwind CSS integration.

Design system: https://design.documenso.com/

Token count: approximately 20-30 core tokens (shadcn default set).

If OTS uses Tailwind v4's `@theme` directive, shadcn's approach is the closest comparison. Their tokens are minimal but extensible.

### Zitadel

Token approach: Not CSS-variable-based. Colors stored as hex strings in the `LabelPolicy` entity and applied through Angular Material theming. Four color categories (background, primary, warn, font) with separate light/dark values. Simpler than a design token system but more structured than raw CSS.

### Keycloak

Token approach: None. Raw CSS files per theme. No design token abstraction. Theme properties files reference CSS includes but don't define tokens.

### Comparison: Design Token Maturity

| Product | Token Count (est.) | Naming Convention | Hierarchy | Dark Mode | Responsive Tokens |
|---|---|---|---|---|---|
| GitLab/Pajamas | 200-400 | `group.component.property.state` | 3-tier (constant/semantic/contextual) | Yes, per-token | No |
| Cal.com | 30-50 | `--cal-category-variant` | Flat | Yes, `.dark` class | No |
| Documenso | 20-30 | shadcn conventions (`--background`, `--primary`) | Flat | Yes, class-based | No |
| Zitadel | ~8 | Angular Material conventions | Flat | Yes, separate policy | No |
| OTS | 44 shades + semantic | oklch-generated | Flat (generated) | Yes, auto from same input | No |

### OKLCH Ecosystem Context

Relevant to OTS's 44-shade oklch palette approach, the open-source ecosystem includes:

- **Evil Martians' oklch-picker**: Promotes oklch for CSS, includes PostCSS polyfill. The canonical reference implementation.
- **oklch.fyi**: Color picker/generator/converter with UI component preview and CSS/Tailwind variable export. Algorithm generates shades by varying lightness while maintaining static hue.
- **ColorBox oklch palette generator**: Professional palette generation with customizable curves for hue, saturation, and luminosity.
- **Atmos (atmos.style)**: OKLCH color tool with APCA contrast formula support for accessible palette creation.
- **Figma plugins**: Paletto (oklch palette generator from single hex), OK Palette (tonal palettes), OkColor (contrast checking).
- **Various GitHub projects**: ccozens/palettePicker (10-swatch ranges), daHatta/demo-oklch-color-palette, abrookst/OKLAB-Palette-Generator.

No open-source project was found that generates full design system palettes from a single hex input using oklch and applies them as a runtime theme system. The tooling ecosystem is oriented toward design-time palette selection, not runtime palette generation. OTS's approach of computing 44 shades at runtime from one input and injecting them as CSS custom properties sits in unoccupied space between design tools and application theming.

---

## 7. Strengths and Gaps

### Where OTS is furthest ahead

**Palette generation from a single input.** This is not a convenience feature; it's an architectural decision that constrains complexity. Every other project in this set requires the operator to think about multiple color values, understand color relationships, or accept preset themes. OTS computes the entire system from one hex value using oklch color space. The technical sophistication (perceptual uniformity, lightness-based shade generation) is invisible to the operator but produces measurably better results than manual token entry. No other surveyed project attempts this.

**Shared install/runtime mechanism.** The same CSS custom properties serve both deployment-time configuration and page-load-time rendering. Most other projects have separate code paths: Mattermost has `config.json` for system branding and user preferences for themes. Chatwoot has `installation_configs` for global and account settings for per-tenant. GitLab has the `appearances` table for admin and design tokens for component theming. Having one mechanism reduces surface area for bugs and makes the system more predictable.

**Tailwind v4 @theme extensibility.** No other project in this set uses Tailwind v4. The `@theme` directive means custom themes can extend the design token system without forking source or editing config files. This is a forward-looking architectural characteristic that becomes more valuable as the feature surface grows.

### Where OTS has the most ground to cover

**No logo support.** Seven of nine projects with branding features support at least one logo upload. GitLab supports three (nav, sign-in, favicon). Zitadel supports separate light/dark logos plus icons. Chatwoot supports three variants. OTS supports zero. For any operator whose brand identity centers on a mark or wordmark, this is a hard blocker for private-labeling. Logo support is table stakes for private-label deployment.

**No admin UI.** GitLab has a dedicated Appearance panel with API. Zitadel has a full console with preview. Mattermost has System Console. Chatwoot has Super Admin. Documenso has org settings. OTS requires config file or environment variable editing. This means branding changes require deployment access, which excludes non-technical stakeholders and makes iteration slower. The absence of an admin UI also means no validation, no preview, and no audit trail.

**No email branding with assets.** Most projects surveyed support a logo or significant customization in emails. Documenso supports custom sender domains with DKIM. GitLab supports custom sender domains. OTS has `brand_color` and `logo_alt` text. Email is often the first branded touchpoint with end users, and text-only branding reads as unfinished.

**No favicon or PWA manifest.** GitLab has both; Zitadel has favicon via icon upload. These are low-effort, high-visibility brand identity elements. Browser tabs and bookmarks displaying the wrong favicon break the private-label illusion immediately.

**Corner style is broken.** Having a feature that does not work is worse than not having it. It signals incomplete implementation and erodes confidence in the branding system overall.

---

## 8. Opportunities

### Gaps no surveyed project fills

**Brand preview mode.** Only Zitadel offers a preview of branding changes before applying them, and theirs is limited to the login screen. No surveyed project offers a full-application preview that renders the complete UI with proposed brand changes before committing. A preview mode that covers the full application surface would be unique and compelling, especially for operators managing branding on behalf of clients.

**Auto-contrast computation.** OTS already has the oklch infrastructure to compute text color contrast automatically per shade. If text color selection were derived from lightness values rather than configured manually, it would eliminate the `button_text_light` configuration field entirely and prevent accessibility failures. No other project attempts this.

**Dark theme auto-generation from the same primary color.** A fully automated semantic alias remapping that produces a complete dark theme from the same input hex would be unique. Currently, GitLab generates a separate `application_dark.css` stylesheet. Mattermost requires separate theme JSON for dark mode. Cal.com maintains separate CSS variable blocks. Zitadel and Rallly require separate color entries per mode. Auto-generating both from one input would extend OTS's single-source approach further.

**Semantic color aliases.** GitLab's design token system uses semantic names (`--gl-text-subtle`, `--gl-bg-default`) that abstract away raw color values. OTS's palette generates shades but does not map them to semantic roles like "surface," "on-surface," "primary-container," "on-primary-container." Adding a semantic layer would make the palette system more useful to theme extenders without requiring them to understand which shade number to use for which purpose.

**Runtime palette generation as a design tool category.** The OKLCH tooling ecosystem is oriented toward design-time palette selection. No tool generates palettes at runtime for application theming. OTS could position this capability as infrastructure that other projects could adopt, not just an internal feature.

### Gaps fillable with moderate effort

**Favicon support.** Accept an image upload or URL, serve it from the appropriate route. Closes a visible gap with minimal architectural change.

**Basic logo support.** Even a single logo slot (header and emails) moves OTS from "absent" to "adequate" on the most-cited gap.

**Email logo injection.** If logo support exists, inserting it into email templates is incremental. Combined with the existing `brand_color`, this moves email branding from "weak" to "adequate."

---

## 9. Ecosystem Trends

### Investment patterns

**GitLab's design token system is maturing.** Migration from SCSS variables to semantic CSS custom properties is progressing. If they expose design token overrides through the Appearance API (currently they don't), they would surpass every project in this set on theming depth. Their Pajamas design system with ~100 components means token changes would cascade consistently. The gap between "tokens exist internally" and "tokens are admin-configurable" is not large.

**Identity/auth projects lead on branding architecture.** Zitadel and Keycloak both have more developed branding systems than most application-layer products. This makes sense: login screens are trust surfaces where branding is a security signal. Zitadel's two-tier model with preview and API, and Keycloak's full template control per realm, reflect this. If OTS treats its interface as a trust surface (which it is, for a secrets tool), the identity/auth projects are the more relevant reference set than the application-layer ones.

**Documenso's multi-tenant branding architecture is the most complete** among application-layer projects. Organization-level settings with team-level overrides, custom email domains with DKIM, per-org sender addresses, and CSS variables for embedded flows. If OTS moves toward multi-tenant or managed-service scenarios, Documenso's schema is the reference implementation.

**Cal.com's commercial framing of private-labeling as a paid tier.** Even with thin technical implementation, Cal.com successfully monetizes branding through plan gating. This validates market demand for private-labeling features but also signals that the market may accept "remove our brand" as sufficient private-labeling for many use cases.

**Rallly's recent private-labeling work** (v4.6.0, January 2026) in a similar-scope product validates that even simple tools see demand for private-labeling. Their implementation is straightforward (env vars + admin UI, primary colors per mode, logo slots, attribution toggle) and worth examining as a reference for minimum viable private-labeling.

**OKLCH adoption is growing in design tooling but not in application theming.** The ecosystem is rich with design-time tools (pickers, palette generators, Figma plugins) but no application-layer project uses oklch for runtime theming. OTS is early in an adoption curve that hasn't reached application infrastructure yet.

### Widening gaps

**The broken corner style feature.** If the branding system's only unique UI-surface features (corner style, font config) are partially broken, operators are unlikely to take the "advanced theming" positioning seriously.

**Config-file-only administration.** As other projects add admin UIs and APIs for branding, the gap in operator experience widens. The trend across this set is toward UI-based brand management, with Zitadel setting the high-water mark (console + API + preview).

**Hardcoded brand references as a class of bug.** Chatwoot's experience with brand references leaking into unexpected surfaces (AI tooltips, WhatsApp replies) is a warning. Any project claiming private-label support needs systematic auditing for hardcoded brand strings, not just configurable surfaces.

---

## 10. Strategic Implications

### Parity vs. differentiation

**Parity targets** (close the gap, match the market):

- Logo support (at least one slot): every serious private-label evaluation starts here
- Favicon: low effort, high visibility
- Fix corner style: a broken feature is a negative signal
- Basic admin UI or API for branding: does not need to be Zitadel-scale, but config-file-only is an outlier

**Differentiation investments** (extend what's distinctive):

- Auto-contrast computation: makes the palette system smarter and removes a config field
- Dark theme auto-generation: extends the single-source-color advantage into the most-requested theming dimension
- Semantic color aliases: makes the palette system usable by theme extenders without shade-number expertise
- Brand preview mode: nearly unique in the surveyed set (only Zitadel has limited preview), high perceived value

**Monitor but do not invest yet**:

- Per-org branding: only relevant if OTS moves toward multi-tenant SaaS
- Custom email sender domains: high effort (DKIM, SPF, DNS verification), niche demand for a secrets tool
- PWA manifest: GitLab is the only one doing this; unclear if the market values it
- Full FreeMarker-style template override: Keycloak's experience shows this creates more operational pain than it solves

### Architecture observation

OTS's palette generation system is technically ahead of every other project in this set. The concern is that this capability is invisible to operators who evaluate branding by checking boxes: "Can I upload a logo? Can I change the favicon? Is there an admin panel?" The palette system is sophisticated but does not produce the artifacts that operators expect in a private-label feature comparison.

The identity/auth products (Zitadel, Keycloak) are more architecturally relevant comparisons for OTS than the application-layer ones. OTS shares their trust-surface characteristic: users make security decisions (sharing secrets, viewing secrets) in the branded interface. The branding needs to reinforce trust, not just match a color scheme.

### Sequencing observation

The visible gaps (logo, favicon, admin UI) determine whether operators take the branding system seriously enough to discover the sophisticated parts (palette generation, oklch, @theme extensibility). Closing visible gaps first ensures the branding system passes checkbox evaluation, then differentiation on palette and theming features that no other project matches becomes discoverable.

---

## Appendix A: Projects Recommended for Hands-On Testing

1. **Zitadel**: Most relevant architectural comparison. Trust-focused, two-tier branding, preview, API. Deploy and test the full branding pipeline including preview and org-level override.
2. **Rallly**: Most similar scope. Recent private-label work (v4.6.0). Test the env-var + admin UI configuration flow.
3. **Keycloak**: Most extensive theming. Test the effort level for basic brand customization, theme inheritance, and cache invalidation behavior.
4. **Documenso**: Most complete multi-tenant branding. Test org-level branding, team override, email domain verification, and embedded signing CSS variables.
5. **GitLab**: Most developed admin branding. Test the Appearance API CRUD, logo upload slots, and email branding toggle.
6. **Chatwoot**: Test Community Edition private-labeling difficulty to establish the pain baseline.

### Testing notes

- Test with oklch-generated colors specifically (since that's OTS's approach) to see whether each product's color system handles perceptual uniformity.
- Document configuration surface counts per product (how many fields, how many clicks, how many files to edit).
- Capture email rendering across clients for each product's branded emails.
- Note mobile rendering behavior for each product's branded surfaces.

## Appendix B: Tool & Infrastructure Reference

| Category | GitLab | Mattermost | Cal.com | Chatwoot | Documenso | Plausible |
|---|---|---|---|---|---|---|
| **Language** | Ruby | Go | TypeScript | Ruby | TypeScript | Elixir |
| **Web framework** | Rails | Custom | Next.js (migrating to App Router) | Rails 7 | React Router + Vite | Phoenix |
| **JS framework** | Vue.js | React + Redux | React + React Query | Vue.js 3 + Vuex | React + tRPC React Query | Phoenix LiveView |
| **CSS** | Tailwind + SCSS | SCSS + CSS vars | Tailwind | SCSS + Bourbon (BEM) | Tailwind + shadcn/ui | Tailwind |
| **Database** | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL | PostgreSQL + ClickHouse |
| **ORM** | ActiveRecord | Custom | Prisma | ActiveRecord | Prisma (+ Kysely) | Ecto |
| **Background jobs** | Sidekiq | Go goroutines | Inngest | Sidekiq | Inngest | Oban |
| **API style** | REST (Rails) | REST + WebSocket | tRPC + REST v2 | REST (Rails) | tRPC + ts-rest | REST |
| **Auth** | Devise | Custom | NextAuth.js + SAML | Devise | Custom + SAML | Custom (Phoenix) |
| **Design system** | Pajamas | Compass (deprecated) | Cal Atoms + Radix | BEM conventions | shadcn/ui | None |
| **Email** | Rails mailers | Go SMTP | react-email + Nodemailer | Rails mailers | react-email + Nodemailer | Bamboo + Mailgun |
| **File storage** | Local + object storage | Local + S3 | S3 | ActiveStorage | S3 (pre-signed URLs) | - |

---

*Analysis date: February 8, 2026. Projects surveyed: 10. Feature comparisons based on current public documentation, source code, GitHub issues, and community forums. Landscapes shift; verify specific claims before using in external-facing materials.*
