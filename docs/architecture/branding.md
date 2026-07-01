# Brand System Architecture

OTS supports private-label deployments. Brand values resolve through a
three-tier fallback — most specific (per-domain) to most generic (neutral) — so
an install never accidentally shows OTS identity when unbranded or when
bootstrap fails.

Operator how-to (setting `BRAND_*`, favicon overrides):
[branding-favicon](../product/branding-favicon.md).

## Fallback chain

```
1. domain_branding (Redis, per custom domain)
   ↓ if null/absent
2. bootstrap config (OT.conf['brand'], from BRAND_*)
   ↓ if null/absent
3. NEUTRAL_BRAND_DEFAULTS (frontend constants)
```

**Step 1 — per-domain (Redis).** Custom domains store their own brand in
`CustomDomain#branding` (`BrandSettings`, 22 fields, WCAG-AA validated).
Delivered to the frontend as `domain_branding` in the bootstrap payload.

**Step 2 — site-wide (OT.conf).** `BrandSettingsConstants.global_defaults` reads
`OT.conf['brand']` at runtime. The `brand:` block in
`etc/defaults/config.defaults.yaml` exposes the `BRAND_*` ENV vars; every key
defaults to `nil`, so no OTS values ship in YAML — neutralization lives in the
Ruby resolvers (#3049), and an absent section falls through to step 3.

**Step 3 — neutral fallback.** When no brand data is present (the common
self-hosted case), the frontend uses `NEUTRAL_BRAND_DEFAULTS`
(`src/shared/constants/brand.ts`): neutral blue `#3B82F6`, product name
`"Secure Links"`. The deprecated `DEFAULT_BRAND_HEX` (`#dc4a22`, OTS orange) is **not**
the fallback — it is retained only where OTS-orange is specifically intended
(e.g. palette-generator tests).

## Config keys

Each `BRAND_*` ENV var populates `OT.conf['brand'][...]` → a `brand_*` bootstrap
field. No defaults shipped.

| ENV var                                | Purpose                                      |
| -------------------------------------- | -------------------------------------------- |
| `BRAND_PRIMARY_COLOR`                  | base hue for the generated palette           |
| `BRAND_PRODUCT_NAME`                   | product name / manifest name                 |
| `BRAND_PRODUCT_DOMAIN`                 |                                              |
| `BRAND_SUPPORT_EMAIL`                  |                                              |
| `BRAND_CORNER_STYLE`                   | `rounded` \| `square` \| `pill`              |
| `BRAND_FONT_FAMILY`                    | `sans` \| `serif` \| `mono`                  |
| `BRAND_BUTTON_TEXT_LIGHT`              |                                              |
| `BRAND_ALLOW_PUBLIC_HOMEPAGE` / `_API` |                                              |
| `BRAND_LOGO_URL`                       |                                              |
| `BRAND_FAVICON_URL`                    | `/favicon.ico` 302 redirect                  |
| `BRAND_APPLE_TOUCH_ICON_URL`           | head `apple-touch-icon`                      |
| `BRAND_OG_IMAGE_URL`                   | head `og:image` / `twitter:image` (absolute) |
| `BRAND_TOTP_ISSUER`                    | MFA issuer label                             |
| `BRAND_SIGNATURE_NAME`                 | email sign-off (see Special cases)           |

## CSS palette

`generateBrandPalette(hex)` (`src/utils/brand-palette.ts`) emits 44 CSS custom
properties — 4 groups × 11 shades — written to `document.documentElement` by
`useBrandTheme()`. Tailwind maps `theme.colors.brand.*` to these vars, so
`bg-brand-500`, `text-branddim-300`, `border-brandcomp-700` all work.

Naming: `--color-{prefix}-{shade}`.

| Prefix         | Source                          |
| -------------- | ------------------------------- |
| `brand`        | base hue, full chroma           |
| `branddim`     | base hue, L×0.84, C×0.90        |
| `brandcomp`    | complement (+180°), full chroma |
| `brandcompdim` | complement, dimmed              |

Shades `50…950`; `500` is the supplied base, `<500` lightens (sqrt curve →
`L_MAX 0.98`), `>500` darkens (linear → `L_MIN 0.25`). Generation runs on mount
and on `primaryColor` change; the last `(hex → palette)` result is memoized in
module scope.

## Static icon assets

The favicon/social-icon pack is a parallel concern: static files in
`public/web/` (not resolved strings), generated brand-neutral from one keyhole
glyph by `scripts/branding/`. Override precedence mirrors the colour chain:
per-domain icon (Redis) → site-level (`BRAND_*_URL`, or a file dropped in
`docker/public/` at build / mounted over `public/web` at runtime) → neutral
default.

SVG-favicon gate: browsers prefer an SVG `<link rel="icon">` over `.ico`, so the
neutral `/favicon.svg` link is emitted **only** for default installs with no
`brand.favicon_url` — otherwise it is suppressed so it cannot shadow a
higher-precedence favicon. Routes: `/favicon.ico` (`get_favicon.rb`) and
`/site.webmanifest` (`get_webmanifest.rb`, overlays product name/colour onto the
neutral manifest). Full how-to:
[branding-favicon](../product/branding-favicon.md).

`scripts/branding/mark.mjs` is the single source of truth for the mark geometry
and neutral palette (`pnpm run gen:favicons` rasterizes the pack). Its three
constants — `PRIMARY_COLOUR`, `BACKGROUND_COLOUR`, `KEYHOLE_PATH` — read
generator-only env vars (`MARK_PRIMARY_COLOR`, `MARK_BACKGROUND_COLOR`,
`MARK_PATH`; deliberately not the runtime `BRAND_*` vars, to keep an ambient
`BRAND_PRIMARY_COLOR` from polluting the neutral defaults), so operators can
generate a custom-coloured pack without editing the source. See the Usage block
in that file.

## Special cases

- **Email templates** can't use CSS vars — brand colour must be inline hex from
  `TemplateContext` helpers (`lib/onetime/mail/views/base.rb`), never template
  literals.
- **Email sign-off** (`signature_name`) is a brand value, not the old hardcoded
  `"Delano"` i18n string: per-message override → `BRAND_SIGNATURE_NAME` →
  neutral i18n default (`"Support Team"`). Deliberately decoupled from
  `product_name`. Per-domain sign-off is intentionally not implemented — no
  domain-scoped email consumes it yet.
- **SecretPreview.vue** uses inline styles on purpose — it shows the _creating_
  domain's brand, not the current context's.

## Validation (write-time, API)

- **Colour**: 3/6-digit hex, expanded + uppercased; WCAG-AA ≥3:1 vs white.
- **Font**: `sans` \| `serif` \| `mono` (case-insensitive).
- **Corner**: `rounded` \| `square` \| `pill` → `rounded-md` \| `rounded-none` \| `rounded-xl`.
- **URLs** (`logo_url`, `favicon_url`): HTTPS or `/`-relative, ≤2048 chars, no
  protocol-relative `//`.
- **Default TTL**: positive integer seconds.

## Private-label checklist

- [ ] `BRAND_PRIMARY_COLOR`, `BRAND_PRODUCT_NAME` (required to override neutral
      blue / `"Secure Links"`)
- [ ] `BRAND_SUPPORT_EMAIL`, `BRAND_LOGO_URL` (or per-domain logo via the
      CustomDomain API)
- [ ] Clear `BRAND_*` → verify neutral theme appears (fallback works)
- [ ] Confirm email templates render brand colour inline
- [ ] WCAG-AA check on the chosen colour
