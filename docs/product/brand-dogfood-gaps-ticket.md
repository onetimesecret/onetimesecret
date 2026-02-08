Brand customization: close dogfood gaps across text, visual, and contextual identity

**Labels**: `brand-system`, `enhancement`

## Summary

The brand customization system is ~70% dogfood-ready. Color pipeline works end-to-end. The remaining gaps mean a self-hosted install with `BRAND_PRODUCT_NAME=Acme` and `BRAND_PRIMARY_COLOR=#0066FF` still shows OTS branding in emails, TOTP, favicon, page titles, and error pages.

This ticket tracks closing those gaps across three rings of work, ordered by impact.

Reference: `docs/product/brand-customization-system.md` (Sections 5 and 7)

## Ring 1 — Neutralize Text Identity (~11 items)

A self-hosted install with brand config should see zero OTS text branding.

- [ ] Change all `'Onetime Secret'` fallbacks to neutral defaults in active codebase
- [ ] Change all `'support@onetimesecret.com'` fallbacks to `'support@example.com'`
- [ ] Change all `'onetimesecret.com'` fallbacks to `'localhost'`
- [ ] Make TOTP issuer read from `brand.product_name` (`mfa.rb`, `totp.rb`)
- [ ] Fix `error.rue` to use template variable for support email
- [ ] Remove deprecated `apps/web/auth/mailer.rb` (10-year-old code, no active references)
- [ ] Make `bootstrapStore` default `brand_product_name` neutral
- [ ] Make `usePageTitle` derive `DEFAULT_APP_NAME` from bootstrapStore
- [ ] Fix `OtpSetupWizard.vue` fallback
- [ ] Fix `OnetimeSecretIcon.vue` title
- [ ] Neutralize `config.defaults.yaml` `site_name` default

**Validation**: Deploy a test instance with custom brand config. Grep all rendered HTML, emails, and TOTP QR codes for "Onetime Secret" or "onetimesecret" — zero matches expected.

## Ring 2 — Visual Identity Config (7 features)

OTS's own visual identity should be expressed through config. Default installation renders with neutral visuals.

- [ ] Add `brand.logo_url` config field (ENV: `BRAND_LOGO_URL`). URL validation: `https://` only, no redirects, max 2MB. See product bible Section 11 (Security).
- [ ] Wire `logo_url` into MastHead as install-level fallback
- [ ] Wire `logo_url` into email templates (replacing hardcoded SVG path)
- [ ] Generate SVG favicon from brand primary color
- [ ] Add dynamic `<meta name="theme-color">` from brand color
- [ ] Implement `corner_style` runtime bridge (composable or CSS var)
- [ ] Conditional font loading — only load Zilla Slab when `font_family: serif`
- [ ] Create neutral default logo asset (geometric, uses brand color via `currentColor`)

**Validation**: Two test instances side by side — one with OTS config, one with custom brand. Both should look equally polished. The custom brand instance should have zero OTS visual artifacts.

## Ring 3 — Contextual Identity (10+ items)

Best-in-class private-label.

- [ ] Auto-compute text contrast per shade (oklch lightness threshold L > 0.623)
- [ ] FOUC prevention — inject brand CSS inline in `<head>` before Vue hydrates
- [ ] "Powered by" toggle (`brand.show_attribution`)
- [ ] Configurable GitHub/docs URLs or conditional display
- [ ] Terms/Privacy URL config fields
- [ ] Dynamic PWA manifest endpoint
- [ ] Email dark mode resilience audit
- [ ] Social preview image generation (or configurable `og:image` URL)
- [ ] Brand preview mode in admin/settings

## Deliverables

- [ ] `docs/operators/brand-customization.md` — operator-facing quick-start and reference. Assume a very competent executor but no prior knowledge of OTS codebase.
- [ ] Toolchain support for token management, integration, linting, validation and regression testing
- [ ] Improved inline help in `config.defaults.yaml` comments

## Resolved questions

| # | Question | Resolution |
|---|----------|------------|
| 1 | Should defaults be truly neutral or should config ship with OTS values while code has neutral fallbacks? | Truly neutral, with OTS customization shipped as a complete, working example. |
| 2 | Should `corner_style` be a CSS custom property or a composable returning Tailwind classes? | Not a CSS custom property. `corner_style` is meant as proxy for simplifying common brand elements. We can achieve that in more extensible and expressable ways now with Tailwind v4. |
| 3 | What customization level for custom domain customers? Logo? Font? Corner style? | Logo, favicon, social/unfurl content, UI toggles, and custom Tailwind v4 css JIT style. See docs/product/tailwind-v4-capabilities.txt |
| 8 | Audit `apps/web/auth/mailer.rb` for active references before deletion | Just remove. It is based on 10 year old code. |
