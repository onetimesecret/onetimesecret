# disabled-homepage

Dispatcher + variants for the page shown when the homepage secret form is
gated by auth (`auth.required` or `homepage_mode === 'external'`).

## Layout

```
src/apps/secret/views/
├── DisabledHomepage.vue        dispatcher (entry point)
└── disabled/
    ├── useDisabledConfig.ts    derives { variant, props } from stores
    └── variants/
        ├── DisabledV1.vue       default — full hero + trust strip + promo
        ├── DisabledMinimal.vue  small mark + headline + ghost CTA
        └── DisabledLegacy.vue   pre-refresh two-tagline (rollback target)
```

Dispatcher consumes `useDisabledConfig()`, picks a component from a
`Record<DisabledHomepageVariant, Component>`, and `v-bind`s the props
bag. Variants are presentational — no store reads.

## Bootstrap contract

The variant is a **per-domain** setting, living on
`homepage_config.disabled_homepage_variant`
(`schemas/contracts/custom-domain/homepage-config.ts`). It rides the
existing `/homepage-config` endpoint that already gates
`signup_enabled` / `signin_enabled` per custom domain — `null` means
"use the deployment-wide frontend default".

The optional affordance overrides stay on the site-level
`bootstrap.disabled_homepage` block
(`schemas/contracts/disabled-homepage.ts`):

| location                                          | field                       | type                            | semantics                                                |
| ------------------------------------------------- | --------------------------- | ------------------------------- | -------------------------------------------------------- |
| `homepage_config`                                 | `disabled_homepage_variant` | `'v1' \| 'minimal' \| 'legacy' \| null` | which component this domain renders (`null` = default)   |
| `bootstrap.disabled_homepage`                     | `show_promo`                | `boolean \| null`               | tri-state override (`null` = auto, `true/false` = force) |
| `bootstrap.disabled_homepage`                     | `show_what_is_this`         | `boolean \| null`               | same                                                     |

All fields optional with sensible defaults; backend may omit either.
Ruby serializer wiring for the per-domain variant field is TBD —
auto-detection / frontend default applies until then.

## Flipping the variant

Resolution order (highest priority first):

1. **`?variant=<id>` URL query param** — dogfood / debugging escape hatch.
   Read once per page load; invalid values fall through silently.
2. **`homepage_config.disabled_homepage_variant`** — per-domain
   operator config via the `/homepage-config` endpoint.
3. **`DEFAULT_DISABLED_HOMEPAGE_VARIANT`** — frontend constant in
   `schemas/contracts/disabled-homepage.ts`.

Once the Ruby `/homepage-config` endpoint accepts the variant field,
per-domain operator config is the long-term path: PATCH the value, no
frontend release. Until then:

- **Frontend default**: change `DEFAULT_DISABLED_HOMEPAGE_VARIANT` in
  `disabled-homepage.ts`. Requires a frontend release. This is the
  source of truth for unconfigured domains and the canonical site.
- **URL param**: `?variant=legacy` on any disabled-homepage URL.

Override individual feature flags via the site-level bootstrap block —
set `show_promo` / `show_what_is_this` to `true` / `false` / `null`
(= auto).

### Verifying which variant is rendering

Each variant's root element carries a `data-variant` attribute (set by
the dispatcher) so you can inspect in DevTools without a console log.

## Auto-detection (suppressed by overrides)

- **`isBranded`** = `isCustom && !!brand.description`
- **`showPromo`** = unbranded custom domain on a SaaS deployment
  (`!isBranded && isCustom && billing_enabled && !!siteHost`)
- **`showWhatIsThis`** = `!!ui.homepage.public_links.recipient_intro`
  (operator-configured URL is the destination; no URL means no link)

Missing URLs suppress the matching affordance — an operator override
can't resurrect a link to `https:///` or to `null`.

## Centred logo

Priority for the centred mark each variant renders:

1. `logoUri` (custom-domain logo configured by the tenant)
2. Monogram derived from `brand.description` (branded fallback)
3. Default OTS mark

The top-left of the page is intentionally empty (the layout-level
masthead is suppressed for the disabled-homepage routes). That slot is
reserved for a future canonical-brand logo configured at the deployment
level.

## Operator-configured links

| field                                                | env var                                  |
| ---------------------------------------------------- | ---------------------------------------- |
| `ui.homepage.public_links.recipient_intro` (string?) | `HOMEPAGE_PUBLIC_LINKS_RECIPIENT_INTRO`  |

Set in `etc/defaults/config.defaults.yaml` under `site.interface.ui.homepage.public_links`.

## Adding a variant

1. `disabled/variants/DisabledX.vue` — implement against `DisabledHomepageProps`.
2. Register in `VARIANTS` in `DisabledHomepage.vue`.
3. Add `'x'` to `disabledHomepageVariantSchema`.

Unrecognized variant ids fall back to `DEFAULT_DISABLED_HOMEPAGE_VARIANT`
(defense in depth — Zod would already reject the value at parse time).

## Tests

`src/tests/apps/secret/views/useDisabledConfig.spec.ts` covers the
auto-detection matrix, override semantics, href derivation, and
reactivity. No variant snapshot tests — visual regression lives
elsewhere.

## Preview

`/disabled` route (`PreviewDisabled.vue`) renders the dispatcher with
the live masthead and a "preview, not real" notice. Useful for
verifying `LOGO_URL` / `SITE_NAME` / brand color without flipping
`auth.required` on the backend.
