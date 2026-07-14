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

The legacy `site.interface.ui.header.branding` rung (`SITE_NAME`, `LOGO_URL`,
`LOGO_ALT`) is deprecated (#3612) and no longer a runtime tier:
`Config#normalize_brand` absorbs any legacy values into step 2 at boot, so
consumers only ever read the `brand:` block. See
[Legacy migration](#legacy-migration-3612).

**Step 1 — per-domain (Redis).** Custom domains store their own brand in
`CustomDomain#branding` (`BrandSettings`, 22 fields, WCAG-AA validated).
Delivered to the frontend as `domain_branding` in the bootstrap payload.

**Step 2 — site-wide (OT.conf).** `BrandSettingsConstants.global_defaults` reads
`OT.conf['brand']` at runtime. The `brand:` block in
`etc/defaults/config.defaults.yaml` exposes the `BRAND_*` ENV vars; every key
defaults to `nil`, so no OTS values ship in YAML — neutralization lives in the
Ruby resolvers (#3049), and an absent section falls through to step 3.

The YAML block interpolates each `BRAND_*` var as a JSON-quoted scalar
(`&.to_json`) so values with YAML-significant characters parse cleanly instead
of being mangled or aborting the document at boot — a leading `#` (hex
`primary_color`) would otherwise be read as a comment and dropped to `nil`, and a
leading `&`/`*`/`!`, an embedded `: `, or a newline would fail the whole config
load. `Config#normalize_brand` (run in `after_load`) is the authoritative parser:
it re-reads the env vars in Ruby, normalizes blanks to `nil`, and coerces
`button_text_light` to a real boolean (only an explicit `false`, whitespace
tolerant, disables it). An env-set field always wins; when a var is unset, any
value set directly in a YAML config file is left intact.

`normalize_brand` is also where the legacy branding sources land (#3612): when
the `brand:` authority leaves `product_name` / `logo_url` / `logo_alt` nil, it
adopts the deprecated `SITE_NAME` / `LOGO_URL` / `LOGO_ALT` env vars or the
legacy `site.interface.ui.header.branding` YAML values — rejecting `*.vue`
component sentinels (the old `LOGO_URL` default `DefaultLogo.vue` is a
frontend marker, not an asset URL). `normalize_header_layout` runs next: it
migrates the masthead layout knobs to `site.interface.ui.header.logo`
(`link_to` → `href`, plus `show_name` / `prominent`) and deletes the
`branding` subtree so it never reaches the bootstrap payload.

**Step 3 — neutral fallback.** When no brand data is present (the common
self-hosted case), the frontend uses `NEUTRAL_BRAND_DEFAULTS`
(`src/shared/constants/brand.ts`): neutral blue `#3B82F6`, product name
`"Secure Links"`. The deprecated `DEFAULT_BRAND_HEX` (`#dc4a22`, OTS orange) is **not**
the fallback — it is retained only where OTS-orange is specifically intended
(e.g. palette-generator tests).

## Config keys

Each `BRAND_*` ENV var populates `OT.conf['brand'][...]` → a `brand_*` bootstrap
field. No defaults shipped.

| ENV var                      | Purpose                                            |
| ---------------------------- | -------------------------------------------------- |
| `BRAND_PRIMARY_COLOR`        | base hue for the generated palette                 |
| `BRAND_PRODUCT_NAME`         | product name / manifest name                       |
| `BRAND_PRODUCT_DOMAIN`       |                                                    |
| `BRAND_SUPPORT_EMAIL`        |                                                    |
| `BRAND_CORNER_STYLE`         | `rounded` \| `square` \| `pill`                    |
| `BRAND_FONT_FAMILY`          | `sans` \| `serif` \| `mono`                        |
| `BRAND_BUTTON_TEXT_LIGHT`    |                                                    |
| `BRAND_LOGO_URL`             | masthead + email logo, per-domain default          |
| `BRAND_LOGO_ALT`             | logo alt text (falls back to product-name i18n)    |
| `BRAND_FAVICON_URL`          | `/favicon.ico` 302 redirect                        |
| `BRAND_APPLE_TOUCH_ICON_URL` | head `apple-touch-icon`                            |
| `BRAND_OG_IMAGE_URL`         | head `og:image` / `twitter:image` (absolute)       |
| `BRAND_TOTP_ISSUER`          | MFA issuer label (falls back to product name)      |
| `BRAND_SIGNATURE_NAME`       | email sign-off (see Special cases)                 |
| `BRAND_PACK`                 | pack NAME → `etc/branding/` then `public/branding/` (unset ⇒ `default`) |
| `BRAND_ASSETS_DIR`           | explicit pack PATH (wins over `BRAND_PACK`)        |

`BRAND_PACK` / `BRAND_ASSETS_DIR` are the two exceptions to the "populates
`OT.conf['brand']`" rule above: they populate `site.brand_pack` /
`site.brand_assets_dir` and drive the static-icon overlay (#3739), not the
`brand:` value block — see [Static icon assets](#static-icon-assets).

`BRAND_LOGO_URL` is the operator/install logo everywhere: the masthead, email
templates, and the default for custom domains with no uploaded logo — but it is
never rendered *as the operator's* on tenant custom domains (they get their own
upload or the neutral mark, same guard as the wordmark). Emails only emit
absolute `http(s)` URLs; a masthead-oriented relative path degrades emails to a
text-only header.

`brand.allow_public_homepage` / `brand.allow_public_api` are YAML-only keys
(read by `initialize_view_vars.rb`, default `false`) — they have **no** env var
wiring in `Config::BRAND_ENV`.

The TOTP/MFA authenticator issuer resolves `brand.totp_issuer` →
`brand.product_name` → `'OTS'`, so a configured product name brands new MFA
enrollments without a separate issuer setting.

### Legacy migration (#3612)

The `brand:` block is the single authority for brand identity. The legacy
`site.interface.ui.header.branding` path and its unprefixed env vars still work
via the `normalize_brand` fallbacks above, but boot logs a deprecation warning
naming the replacement. These are **soft** deprecations: they only ever warn —
even under `DEPRECATED_CONFIG_MODE=strict` boot is never refused (`silent`
suppresses the warning).

| Legacy           | Replacement                                             |
| ---------------- | ------------------------------------------------------- |
| `SITE_NAME`      | `BRAND_PRODUCT_NAME` (`brand.product_name`)             |
| `LOGO_URL`       | `BRAND_LOGO_URL` (`brand.logo_url`)                     |
| `LOGO_ALT`       | `BRAND_LOGO_ALT` (`brand.logo_alt`)                     |
| `LOGO_LINK`      | `site.interface.ui.header.logo.href` (env unchanged)    |
| `LOGO_SHOW_NAME` | `…header.logo.show_name` (env unchanged)                |
| `LOGO_PROMINENT` | `…header.logo.prominent` (env unchanged)                |

The three layout knobs are *not* deprecated — only their YAML nesting moved
(and `link_to` was renamed `href`). `show_name` is now explicit-only: unset
means "show the wordmark unless a custom brand logo is configured" (custom
logos usually embed their own wordmark). Previously, unset meant always-on —
an install that set `LOGO_URL` and relied on the implicit wordmark should set
`LOGO_SHOW_NAME=true` to keep it.

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

The favicon/social-icon pack is a parallel concern: static files in a **brand
pack** directory (not resolved strings), generated brand-neutral from one
keyhole glyph by `scripts/branding/`. Since v2 (#3774) resolution ALWAYS lands
on a pack — the tracked neutral `default` pack (`public/branding/default/`)
unless an operator selects another. Override precedence mirrors the colour
chain:

```
per-domain icon (Redis)
  ↓ BRAND_FAVICON_URL (302 redirect)
  ↓ selected brand pack (BRAND_PACK / BRAND_ASSETS_DIR, #3739)
  ↓ default brand pack (public/branding/default, #3774)
```

A selected pack may be partial: files it omits fall through to the `default`
pack. A legacy `public/web` runtime mount still resolves as a last-ditch
fallback in `brand_asset_path`.

**Two search roots (#3774).** A `BRAND_PACK` _name_ is resolved across two roots,
first existing wins:

1. `etc/branding/<name>` — operator space. Nothing is tracked here in the repo;
   it arrives at runtime (quadlet per-entry mounts of `/etc/onetimesecret/`,
   systemd confext, a Docker/K8s volume). Checked first so an operator pack
   shadows a vendor pack of the same name.
2. `public/branding/<name>` — vendor space. Ships the tracked `default` pack and
   any generated packs baked into the image/repo.

The `default` pack deliberately lives in the VENDOR root: a quadlet mount of a
host `branding/` dir lands wholesale over `etc/branding`, so a tracked
`etc/branding/default` would be shadowed exactly when packs are in use.

### Brand pack manifest (#3774)

A pack is the single unit of branding: the static assets above **plus** an
optional `brand.yaml` carrying the identity scalars (colours, product name,
etc.) that go with them, so `BRAND_PACK=acme` ships icons + colours + name as
one unit instead of a pack plus a wall of `BRAND_*` vars that nothing keeps in
agreement. Precedence (lowest to highest):

```
built-in defaults  <  pack brand.yaml  <  operator `brand:` config  <  BRAND_* env
```

`Config#apply_brand_manifest` (run in `after_load`, before `normalize_brand`)
`YAML.safe_load`s the resolved pack's `brand.yaml` and fills only the keys the
operator's `brand:` config left nil; env then layers on top. Keys are whitelisted
to `BRAND_MANIFEST_KEYS` (== `BRAND_ENV` keys), so a pack can never reach
`site.host`, SMTP creds, or any non-brand config. The tracked `default` pack
ships a **value-free, all-commented** `brand.yaml`, so an unconfigured install
adds no brand values — `brand.*` stays nil and the frontend `NEUTRAL_BRAND_DEFAULTS`
remain the single authority for neutral rendering (#3049). Drift specs assert the
default manifest stays value-free and that its documented key set equals the
whitelist.

**Runtime overlay (#3739 / #3774).** `BRAND_PACK` (a pack _name_ resolved across
the two roots above) or `BRAND_ASSETS_DIR` (an explicit _path_, e.g. a mounted
volume; wins over `BRAND_PACK`) select a replacement pack. It is applied at three
chokepoints, all routed through the shared `Onetime.brand_asset_path(name)` /
`brand_overlay_dir` / `brand_pack_dir(name)` helpers (`lib/onetime.rb`):

1. **Static middleware** (`StaticFiles`) — the base brand layer serves
   `BRAND_PACK_URLS` from the resolved `default` pack (was `public/web`, #3774);
   a selected pack distinct from `default` mounts an extra `Rack::Static` layer
   ahead of it, listing only the overlay files that actually exist
   (`Rack::Static` matches by URL prefix, not file existence, so a partial pack
   falls through to the default base). App/build assets (`/dist`, `/img`, `/v3`)
   still serve from `public/web` and are never overlaid. The stack is built once
   at boot, so changing packs needs a restart.
2. **`GetFavicon`** — `serve_default_favicon` resolves `favicon.ico`
   overlay-first before the `public/web` fallback.
3. **`GetWebmanifest`** — `load_base_manifest` resolves `site.webmanifest`
   overlay-first (then `public/web`, then the built-in `NEUTRAL_FALLBACK`).

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
- [ ] Migrate any legacy `SITE_NAME` / `LOGO_URL` / `LOGO_ALT` to the `BRAND_*`
      equivalents (deprecated since #3612 — still honored, but boot warns)
- [ ] Clear `BRAND_*` → verify neutral theme appears (fallback works)
- [ ] Confirm email templates render brand colour inline
- [ ] WCAG-AA check on the chosen colour
