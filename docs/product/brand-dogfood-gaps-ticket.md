Brand customization: close dogfood gaps across text, visual, and contextual identity

**Labels**: `brand-system`, `enhancement`

## Summary

The brand customization system is ~70% dogfood-ready. Color pipeline works end-to-end. The remaining gaps mean a self-hosted install with `BRAND_PRODUCT_NAME=Acme` and `BRAND_PRIMARY_COLOR=#0066FF` still shows OTS branding in emails, TOTP, favicon, page titles, and error pages.

This ticket tracks closing those gaps across four priority levels (P0-P3), ranked by dogfood impact. "Gaps" here means the distance between what we intend to build and what the codebase currently reflects — not gaps relative to other projects.

Reference: `docs/product/brand-customization-system.md` (Sections 5 and 7)

## What's Working (and distinctive)

The oklch palette generator is genuinely unique among OSS SaaS projects. No other project we surveyed (GitLab, Mattermost, Chatwoot, Cal.com, Plausible, Documenso, Sentry) generates a full shade palette from a single hex input. The architecture is sound, and this table captures what an executor can treat as settled ground.

| Area                      | Status           | Evidence                                                                                                    |
| ------------------------- | ---------------- | ----------------------------------------------------------------------------------------------------------- |
| Color palette generation  | Production-ready | 44 CSS vars across 4 palettes (brand, brandcomp, branddim, branddimcomp) x 11 shades, oklch, gamut clipping |
| Brand CSS class adoption  | Strong           | 131 files, 404 `brand-*` class usages                                                                       |
| Dark mode pairing         | Good             | Consistent `bg-brand-600 dark:bg-brand-500` patterns                                                        |
| Semantic color separation | Correct          | red/amber/green for UX feedback, NOT brand classes                                                          |
| i18n product name         | Mostly done      | `$t()` with `{ product_name }` in most user-facing strings                                                  |
| Email inline hex          | Correct          | `brand_color` helper outputs hex, not CSS vars (correct for email clients)                                  |
| 3-layer fallback chain    | Working          | domain -> install -> default resolves correctly                                                             |
| MastHead logo chain       | Well-designed    | props -> custom domain -> config -> default                                                                 |

## P0 — Operator WILL see OTS branding despite configuring their own

A self-hosted operator who has set their brand config will still encounter OTS branding in these places. These are blockers for dogfood.

- [ ] **Email logo hardcoded** — `/img/onetime-logo-v3-xl.svg` in all 9 HTML templates (Backend). Add `brand.logo_url` config field and wire it into templates. The existing logo config in `config.defaults.yaml` should be subsumed by the new brand-level field:
  ```yaml
  # (old way) Logo configuration in config.defaults.yaml. Should be subsumed.
  logo:
    # URL to logo image file
    url: <%= ENV['LOGO_URL'] || 'DefaultLogo.vue' %>
    # Alt text for logo image
    alt: <%= ENV['LOGO_ALT'] || 'Share a Secret One-Time' %>
    # Where the logo links to when clicked
    href: <%= ENV['LOGO_LINK'] || '/' %>
  ```
- [ ] **Favicon SVGs hardcode `#DC4A22`** — Browser tab shows OTS orange (Frontend). Generate from brand color or add config.
- [ ] **TOTP issuer hardcoded to `'OneTimeSecret'`** in Rodauth config + TOTP utility (`mfa.rb:24`, `totp.rb:23,51`) (Backend). Read from `brand.product_name`.
- [ ] **Error page hardcodes `support@onetimesecret.com`** (`error.rue:158`) (Backend). Use template variable.
- [ ] **`bootstrapStore` defaults `brand_product_name: 'Onetime Secret'`** (`bootstrapStore.ts:64`) (Frontend). Use neutral default.
- [ ] **`usePageTitle` has `DEFAULT_APP_NAME = 'Onetime Secret'`** (`usePageTitle.ts:36`) (Frontend). Derive from store.
- [ ] **Logo assets are all OTS-branded, no `logo_url` config field exists** (Both). Add installation-level logo config:
  - [ ] Add `brand.logo_url` config field (ENV: `BRAND_LOGO_URL`). URL validation: `https://` only, no redirects, max 2MB. See product bible Section 11 (Security).
  - [ ] Wire `logo_url` into MastHead as install-level fallback
  - [ ] Create neutral default logo asset (geometric, uses brand color via `currentColor`; all current logo files are OTS-branded)

## P1 — Config dimensions that exist but don't work at runtime

These are design dimensions that have schema fields or partial implementation but produce no runtime effect, plus the long tail of hardcoded OTS-specific fallback strings scattered across the codebase.

- [ ] **`corner_style`** — schema field exists, nothing applies it to components; components hardcode border-radius. Build a composable or CSS var bridge.
- [ ] **`font_family`** — Zilla Slab `@font-face` always loads (~100KB), regardless of config. Conditional font loading: only load Zilla Slab when `font_family: serif`.
- [ ] **Fallback strings** — `'Onetime Secret'`, `'support@onetimesecret.com'`, `'#dc4a22'` scattered in ~12 backend locations. Neutralize to `'My App'`, `'support@example.com'`:
  - [ ] Change email `support_email` fallback to `'support@example.com'` (`base.rb:272`)
  - [ ] Change email `site_host` fallback to `'localhost'` (`base.rb:288`)
  - [ ] Fix mail `base.rb` outer method to match inner method's fallback chain (`base.rb:161-163` currently falls back to `'Onetime Secret'`)
  - [ ] Neutralize view bootstrapper fallbacks (`initialize_view_vars.rb:168,181-183` — OTS-specific defaults)
  - [ ] Fix `OtpSetupWizard.vue` fallback (`OtpSetupWizard.vue:37` — use `brand_product_name`)
  - [ ] Fix `OnetimeSecretIcon.vue` title (`OnetimeSecretIcon.vue:55` — use brand `product_name`)
  - [ ] Neutralize `config.defaults.yaml` `site_name` default (`config.defaults.yaml:88` currently reads `'One-Time Secret'`)
  - [ ] Neutralize auth API response (currently returns `'OneTimeSecret'`; internal/diagnostic only)
  - [ ] Grep-audit remaining `'Onetime Secret'`, `'onetimesecret.com'`, and `'support@onetimesecret.com'` fallbacks across the active codebase and neutralize any not covered above
- [ ] Remove deprecated `apps/web/auth/mailer.rb` (10-year-old code, no active references)

**Validation (text identity)**: Deploy a test instance with custom brand config. Grep all rendered HTML, emails, and TOTP QR codes for "Onetime Secret" or "onetimesecret" — zero matches expected.

**Validation (visual identity)**: Two test instances side by side — one with OTS config, one with custom brand. Both should look equally polished. The custom brand instance should have zero OTS visual artifacts.

## P2 — Missing config dimensions (based on OSS survey)

These are capabilities that comparable OSS projects offer but OTS does not yet expose as configuration.

- [ ] **Logo upload/URL** (header + email) — Who has it: GitLab (3 slots), Chatwoot (3), Mattermost, Documenso, Rallly — Impact: High — every private-label needs this
- [ ] **"Powered by" toggle** (`brand.show_attribution`) — Who has it: Rallly, Plausible, Chatwoot — Impact: Medium — enterprise private-label
- [ ] **Terms/Privacy URLs** — Who has it: Mattermost, Cal.com — Impact: Medium — compliance
- [ ] **GitHub/docs URLs hardcoded** in ~10 frontend components — Who has it: None configurable — Impact: Medium — links to upstream
- [ ] **Dynamic PWA manifest** endpoint (currently a static file that cannot reflect per-domain brand) — Who has it: GitLab — Impact: Medium — mobile installs
- [ ] **Social preview image** (og:image) — configurable URL; currently a static OTS-branded PNG — Who has it: None dynamically — Impact: Medium — link sharing
- [ ] **Login/signup page brand customization** — no background image or hero text config; only homepage toggle exists today
- [ ] **Dark theme auto-generation** — `branddim-*` palette exists but there is no single-step light-to-dark theme derivation from the primary color
- [ ] **Email dark mode resilience audit**
- [ ] **Brand preview mode** in admin/settings
- [ ] **DnsWidget brand colors** (~20 hardcoded hex values in third-party widget)

## P3 — Quick wins and long-tail enhancements

Short-effort improvements and longer-horizon private-label capabilities.

**Quick wins from research:**

- [ ] **Auto-compute text contrast per shade** (oklch L > 0.623 threshold) — Effort: ~2 hours — Impact: Removes manual `button_text_light`
- [ ] **Dynamic `<meta name="theme-color">`** from brand primary — Effort: ~30 min — Impact: Browser chrome matches brand
- [ ] **SVG favicon generated from brand color** — Effort: ~3 hours — Impact: Dynamic favicon
- [ ] **FOUC prevention** — inject brand CSS inline in `<head>` before Vue hydrates — Effort: ~4 hours — Impact: No flash of default colors

**Long-tail:**

- [ ] Per-organization branding — multi-tenant orgs within one install currently share a single brand identity
- [ ] Custom email sender name/domain — all emails currently sent from installation default sender; see product bible Section 12
- [ ] Font file upload support — operators cannot upload custom woff2 fonts; see product bible Section 11 for security considerations
- [ ] Per-domain theme extension — operators limited to `primary_color`; no mechanism to set additional CSS custom properties per-domain

## Deliverables

- [ ] `docs/operators/brand-customization.md` — operator-facing quick-start and reference. Assume a very competent executor but no prior knowledge of OTS codebase.
- [ ] Toolchain support for token management, integration, linting, validation and regression testing
- [ ] Improved inline help in `config.defaults.yaml` comments
- [ ] At the end, translate this document into a list of criteria that must be met for ongoing QA

## Resolved questions

| #   | Question                                                                                                 | Resolution                                                                                                                                                                           |
| --- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Should defaults be truly neutral or should config ship with OTS values while code has neutral fallbacks? | Truly neutral, with OTS customization shipped as a complete, working example.                                                                                                        |
| 2   | Should `corner_style` be a CSS custom property or a composable returning Tailwind classes?               | Not a CSS custom property. `corner_style` is meant as proxy for simplifying common brand elements. We can achieve that in more extensible and expressable ways now with Tailwind v4. |
| 3   | What customization level for custom domain customers? Logo? Font? Corner style?                          | Logo, favicon, social/unfurl content, UI toggles, and custom Tailwind v4 css JIT style. See docs/product/tailwind-v4-capabilities.txt                                                |
| 8   | Audit `apps/web/auth/mailer.rb` for active references before deletion                                    | Just remove. It is based on 10 year old code.                                                                                                                                        |

## Open Questions

| #   | Question                                                                                                                                               | Owner       | Status   |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------- | -------- |
| 4   | Should we build an admin Brand Settings UI, or is ENV/config sufficient? No admin.                                                                     | Product     | Answered |
| 5   | Should `button_text_light` become auto-computed (removing the config field)? Yes                                                                       | Engineering | Answered |
| 6   | Implement server-side brand CSS injection in `<head>` or accept FOUC? Server-side injection                                                            | Engineering | Answered |
| 7   | Should email templates support a dark logo variant, or is transparent-background sufficient? Transparent                                               | Design      | Answered |
| 9   | Additional CSS properties per-domain beyond `primary_color`? Full `@theme` override or a curated subset?                                               | Engineering | Open     |
| 10  | What login/signup page elements should be configurable — background image only, or also hero text and layout?                                          | Product     | Open     |
| 11  | Should dark theme auto-generation remap semantic aliases automatically, or require explicit dark palette config?                                       | Engineering | Open     |
| 12  | How should per-organization branding interact with per-domain branding when both are configured? Which takes precedence? Domain determines organization; site uses organization's branding.                              | Product     | Answered     |
| 13  | Should custom email sender domain require DNS verification at config time, or validate lazily on first send?  At customization time.                                        | Engineering | Answered     |
| 14  | Should font file upload be exposed via admin UI, or config/CLI only? What about license compliance checking?  Skip font uploading                                         | Product     | Answered     |
