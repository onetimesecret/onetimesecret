# Backend Insights from Brand Config Landscape Survey

## 1. Config Architecture

### What competitors do:

- Rallly: ENV-only, no database fields, readonly admin UI is a dead end
- Zitadel: Pure API/database, no config files at all, single LabelPolicy domain object
- Documenso: Database-only via Prisma models, no ENV vars for branding

### Where OTS sits today:

OTS has a hybrid model that is closer to where Rallly wants to be. The `brand:` section in
`/Users/d/Projects/opensource/onetime/onetimesecret/etc/defaults/config.defaults.yaml` provides deploy-time defaults via ERB+ENV (`BRAND_PRIMARY_COLOR`, `BRAND_PRODUCT_NAME`,
etc.). At runtime, `BrandSettingsConstants.defaults` in `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/models/custom_domain/brand_settings.rb` reads
`OT.conf.dig('brand', 'primary_color')` and merges over the frozen `DEFAULTS` hash. Per-domain overrides live in Redis via `CustomDomain#brand` (a Familia hashkey) and
materialize as the immutable `BrandSettings` Data object.

**Key insight:** Rallly's survey shows that stopping at ENV vars is a dead end -- the mutation path from UI to runtime config is the hard part, and Rallly hasn't built it. OTS
already has the mutation path for custom domains (Redis hashkey, V2 API writes), but the install-level config in YAML is still deploy-time only. The gap is: there is no
admin UI or API to change install-level brand settings at runtime without editing config and restarting.

**Caution:** Zitadel's "no config file" approach only works because they went API-first from day one. For OTS, the config file is the right entry point for self-hosted
operators. The risk is building a runtime mutation path for install-level brand that drifts from the YAML source of truth. If an operator sets `BRAND_PRIMARY_COLOR=#ff0000`
in config but then an admin UI writes a different value to Redis, which wins? The resolution order needs to be explicit and documented: YAML/ENV as seed, Redis as
override, with a clear "reset to config default" path.

## 2. Multi-Tenancy (Install-Level vs Per-Domain)

### What competitors do:

- Zitadel: Clean two-tier inheritance. `Query ActiveLabelPolicyByOrg` hits both org and instance rows in one SQL query, ordered so org wins over instance. Partial override
  is fine (set primary color at org, skip warn color, SCSS defaults fill gaps).
- Documenso: Two Prisma models with nullable fields for inheritance. But the code treats branding as all-or-nothing: if `brandingEnabled` is null at team level, it copies
  all four fields from org wholesale. The schema is more expressive than the resolution logic.

### Where OTS sits today:

OTS already has two tiers: install-level (`OT.conf['brand']`) and per-custom-domain (`CustomDomain#brand` hashkey in Redis). The resolution happens in `BrandSettings.from_hash`
at `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/models/custom_domain/brand_settings.rb:84-99` -- it layers `all_nil`, then `BrandSettingsConstants.defaults`
(which reads from `OT.conf`), then the per-domain hash. This means per-domain values override install defaults, and any unset per-domain field falls through to install
config. This is per-field inheritance, which is more expressive than Documenso's all-or-nothing approach.

**Caution:** The current code memoizes `@brand_settings` on the `CustomDomain` instance (line 337). If install-level config changes at runtime (hypothetically via an admin API),
cached `BrandSettings` on already-loaded `CustomDomain` objects will be stale. For now this is fine because config changes require a restart, but it becomes a bug if
install-level brand config becomes mutable at runtime.

**Observation from Zitadel:** Their single-query resolution (both tiers in one query, `LIMIT 1` with ordering) is elegant for SQL but not directly applicable to Redis. The OTS
approach of loading the Redis hashkey and merging over defaults is the idiomatic Redis pattern. The key is that `BrandSettingsConstants.defaults` always reads live from
`OT.conf`, so a restart picks up config changes cleanly.

## 3. Config Serialization (Backend to Frontend)

### What competitors do:

- Rallly: `getInstanceBrandingConfig()` injects 4 CSS custom properties onto `<html>` at render time, per-request
- Zitadel: Generates a static CSS file on activation event, serves it via `<link>` tag with cache-bust query param. Generation happens once, not per request.
- Documenso: No CSS theming, just asset substitution and content injection via React context

### Where OTS sits today:

`InitializeViewVars` at `/Users/d/Projects/opensource/onetime/onetimesecret/apps/web/core/views/helpers/initialize_view_vars.rb:180-188` reads `OT.conf.fetch('brand', {})` and
passes 7 brand values into the view vars hash. `ConfigSerializer` at
`/Users/d/Projects/opensource/onetime/onetimesecret/apps/web/core/views/serializers/config_serializer.rb:50-56` copies those 7 values into the serialized output, which gets
injected into a `<script id="onetime-state">` bootstrap payload. The frontend's `useBrandTheme` composable then reads these and generates the 44-var CSS palette client-side.

**Key insight from Zitadel:** The most important observation from the survey is that CSS generation should happen once on "activation" (save), not per-request. OTS currently
generates the 44-variable oklch palette in the browser on every page load. The survey validates that Zitadel's approach -- generate once, serve static -- is the more
scalable pattern.

For the backend, this would mean: when brand config changes (either install-level or per-domain), generate the CSS palette server-side (Ruby port of `brand-palette.ts`),
store the result (Redis string or file), and serve it as a static asset with cache headers. The `ConfigSerializer` would then pass only metadata (e.g., cache-bust key,
palette URL) rather than raw color values.

**Caution:** A server-side palette generator in Ruby would need to match the oklch color space math exactly. The existing `brand-palette.ts` uses oklch with sqrt lightness
curves. Porting that to Ruby introduces a risk of subtle color drift between server-generated CSS and any client-side fallback. If you go this route, the client-side
generator should be removed entirely, not kept as a fallback.

## 4. Email Templates

### What competitors do:

- Rallly: Does not handle branded emails at all
- Zitadel: Does not handle branded emails either (separate i18n for everything)
- Documenso: Has the most mature email branding. A React `BrandingProvider` wraps email templates, `TemplateFooter` conditionally renders custom company details, logo served
  via dedicated API endpoints (`/api/branding/logo/team/$teamId`) with 1-hour cache + 24-hour stale-while-revalidate

### Where OTS sits today:

All 9 HTML email templates hardcode the logo path as `/img/onetime-logo-v3-xl.svg`. The `TemplateContext` at
`/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/mail/views/base.rb:265-267` provides `brand_color` (resolved from data, config, or `#dc4a22` default), `logo_alt`
(delegates to `product_name`), and `support_email`. The inline style on every logo `<img>` tag uses `background-color: <%= brand_color %>` -- so the brand color is already applied
to emails.

Specific findings:

- Logo path is hardcoded across 9 templates: `<%= baseuri %>/img/onetime-logo-v3-xl.svg`. Not configurable.
- `brand_color` resolution is correct (data > config > hardcoded default), but `product_name` falls back to 'Onetime Secret' and then to `t('email.common.onetime_secret')` at
  line 283. The fallback chain is data > `brand.product_name` config > `site.interface.ui.header.site_name` > i18n key.
- `support_email` falls back to `support@onetimesecret.com` (hardcoded in `TemplateContext` line 272).

Recommendations:

- Add a `logo_url` field to `BrandSettings` and to the `brand:` config section. The email templates should use `<%= logo_url || "#{baseuri}/img/onetime-logo-v3-xl.svg" %>`. This
  is the simplest fix with the highest impact for self-hosted operators.
- Documenso's dedicated logo-serving API endpoint is worth studying. For custom domains that upload logos via the V2 API (the hashkey `:logo` on `CustomDomain`), a route like
  `/api/v2/brand/logo/:domain_extid` that serves the stored image with proper cache headers would let email templates reference a stable URL.
- The `support_email` hardcoded fallback should come from `BrandSettingsConstants::DEFAULTS` (it is already in config but the `TemplateContext` fallback is a separate hardcoded
  string).

## 5. TOTP/MFA Issuer

### What competitors do:

None of the three surveyed projects address this. Zitadel handles MFA internally but the `otp_issuer` is not part of `LabelPolicy`. It is a gap across the board.

### Where OTS sits today:

The Rodauth configuration at `/Users/d/Projects/opensource/onetime/onetimesecret/apps/web/auth/config/features/mfa.rb:24` hardcodes `auth.otp_issuer 'OneTimeSecret'`. The
utility class at `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/utils/totp.rb:23` also hardcodes `issuer: 'OneTimeSecret'` as a default parameter, and line 51
hardcodes it in `verify` without even accepting it as a parameter.

This matters: When a self-hosted operator white-labels the product as "AcmeCorp Secrets" and their users set up TOTP, their authenticator app shows "OneTimeSecret" as the
issuer. This undermines the branding effort at a critical trust point. If the user doesn't recognize "OneTimeSecret," they may not associate the TOTP entry with their
AcmeCorp account.

Recommendation: Add `totp_issuer` to the `brand:` config section (defaulting to `'OneTimeSecret'`). Wire it into Rodauth config:
`auth.otp_issuer OT.conf.dig('brand', 'totp_issuer') || 'OneTimeSecret'`

**Caution:** Changing the TOTP issuer after users have enrolled invalidates their existing TOTP setup. The issuer is part of the `otpauth://` URI that authenticator apps store.
A changed issuer means users see a new entry in their authenticator and the old one still works but shows the wrong name. This should be documented as a one-time-at-setup
configuration, not something to change after users have enrolled. The `verify` method in `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/utils/totp.rb:51` does
not actually use the issuer for verification (TOTP verification is issuer-independent), so changing it is cosmetic but confusing.

## 6. Asset Management (Favicon, Logo, PWA Manifest)

### What competitors do:

- Rallly: `logoIcon` from ENV, rendered as `<img>` tag, simple asset substitution
- Zitadel: Separate icon and logo fields, both light/dark variants, uploaded via API, served through dynamic resource handler that resolves org vs instance assets by
  request context
- Documenso: Logo stored as JSON-serialized file reference in database, served through dedicated API endpoint per org/team

### Where OTS sits today:

- Favicon: Served statically from `public/web` via `Rack::Static` at `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/middleware/static_files.rb:67`. Not
  configurable.
- PWA manifest: Commented out in the head template at `/Users/d/Projects/opensource/onetime/onetimesecret/apps/web/core/templates/partials/head-base.rue:19`.
  `site.webmanifest` is a static file. Not configurable.
- Theme color: Already dynamic -- `<meta name="theme-color" content="{{brand_primary_color}}">` at line 20 of the same template.
- Logo: `CustomDomain` has hashkey `:logo` and hashkey `:icon` (lines 104-105 of `custom_domain.rb`), so per-domain logo upload is partially scaffolded in the data model but there
  is no serving route.

Recommendations:

- For favicon, the lowest-effort approach is a Rack middleware that intercepts `/favicon.ico` and serves a configurable path. Do not try to generate favicons from the brand
  color -- that is scope creep.
- For PWA manifest, a dynamic route that renders `site.webmanifest` from brand config (name, `short_name`, `theme_color`, icons) would be straightforward. The manifest is just
  JSON.
- The hashkey `:logo` and hashkey `:icon` on `CustomDomain` are the right Redis structures for storing uploaded binary assets. What is missing is the serving route and the
  upload validation (dimensions, format, file size). Zitadel's per-asset removal API (`RemoveCustomLabelPolicyLogo`, etc.) is a useful pattern -- each asset should be
  independently settable and removable.

**Caution:** Storing binary image data in Redis hashkeys works for small assets (favicon, logo) but is not appropriate for large images. The comment at
`/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/models/custom_domain/features/safe_dump_fields.rb:28` ("We don't include brand images here b/c they create
huge payloads") confirms this is already understood. Consider a maximum size limit (e.g., 256KB) enforced at upload time.

## 7. Validation

### What competitors do:

- Zitadel: Hex color validation via regex `^$|^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$`. Empty string is valid (means "use default"). State lifecycle on `LabelPolicy` (Unspecified,
  Active, Removed, Preview) provides structural validation.
- Rallly: Defaults defined as constants, dark color auto-derived from light via iterative contrast adjustment (up to 20 iterations targeting WCAG 3.0+ ratio). No explicit
  validation of input.
- Documenso: Schema-level defaults (non-nullable with defaults at org, nullable at team). No input validation beyond Prisma schema constraints.

### Where OTS sits today:

`BrandSettings` at `/Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/models/custom_domain/brand_settings.rb` provides three validation methods:

- `valid_color?` -- regex `^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$` (matches Zitadel's pattern minus the empty-string allowance)
- `valid_font?` -- checks against `FONTS = %w[sans serif mono]`
- `valid_corner_style?` -- checks against `CORNERS = %w[rounded square pill]`

Boolean coercion from string `"true"/"false"` is handled by `coerce_boolean`.

**Gap:** These validators exist but are not called during `from_hash`. The factory method applies defaults and coerces booleans but does not reject invalid colors, fonts, or
corners. Invalid values pass through silently. This means the V2 API endpoint that writes to `CustomDomain#brand` must do its own validation before calling `from_hash`, or
invalid data lands in Redis.

Recommendation: Add a `validate!` method to `BrandSettings` that raises on invalid values, and call it at the API boundary (not in `from_hash`, since `from_hash` is also used when
reading from Redis, where we want to be tolerant of existing data). This follows the "be liberal in what you accept from storage, strict in what you accept from input"
principle.

Missing validations:

- URL format validation for any future `logo_url` field
- Image dimension/size validation for uploaded logos (Documenso stores as JSON file reference, which implicitly bounds what gets stored)
- `default_ttl` range validation (currently accepts nil but has no max bound)
- locale validation against available locales

---

### Summary of Priorities for Backend Work

|                           Area | Current State                         | Survey Insight                                     | Risk Level                          |
| -----------------------------: | :------------------------------------ | :------------------------------------------------- | :---------------------------------- |
|                    TOTP issuer | Hardcoded 'OneTimeSecret' in 3 places | Nobody handles this well; easy win                 | Low risk, high branding impact      |
|                     Email logo | Hardcoded SVG path in 9 templates     | Documenso's dedicated logo endpoint is the pattern | Low risk, moderate effort           |
|               Input validation | Validators exist but are not enforced | Zitadel validates at API boundary                  | Medium risk (invalid data in Redis) |
| Install-level runtime mutation | Config file only, restart required    | Rallly's unbuilt bridge is a cautionary tale       | High risk if attempted prematurely  |
|                 CSS generation | Client-side per-request               | Zitadel generates once on activation               | Medium risk (oklch port fidelity)   |
|               Favicon/manifest | Static files, not configurable        | Zitadel's dynamic asset handler                    | Low risk, nice-to-have              |
