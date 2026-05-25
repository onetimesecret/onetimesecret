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

`bootstrap.disabled_homepage` (`schemas/contracts/disabled-homepage.ts`):

| field               | type                                   | semantics                                              |
| ------------------- | -------------------------------------- | ------------------------------------------------------ |
| `variant`           | `'v1' \| 'minimal' \| 'legacy'`        | which component to render                              |
| `show_promo`        | `boolean \| null`                      | tri-state override (`null` = auto, `true/false` = force) |
| `show_what_is_this` | `boolean \| null`                      | same                                                   |

All fields optional with sensible defaults; backend may omit the block.
Ruby serializer wiring is TBD — auto-detection rules apply until then.

## Flipping the variant

Resolution order (highest priority first):

1. **`?variant=<id>` URL query param** — dogfood / debugging escape hatch.
   Read once per page load; invalid values fall through silently.
2. **`bootstrap.disabled_homepage.variant`** — operator config via
   server-injected window state.
3. **Schema default** in `disabled-homepage.ts`.

Once the Ruby serializer emits `disabled_homepage`, operator config is
the long-term path: change the value, bounce the app, next page load
picks it up. No frontend release. Until then:

- **Schema default**: change `disabledHomepageVariantSchema.default('v1')`.
  Requires both a frontend release *and* regenerating the JSON schemas
  Rhales reads (`pnpm run schemas:rhales:generate`) — Rhales applies
  defaults server-side, so a frontend-only change is invisible.
- **Bootstrap window state**: inject in the Ruby HTML template before
  the bundle loads, e.g.
  `window.__BOOTSTRAP_ME__.disabled_homepage = { variant: 'legacy', ... }`.
  Per-deployment, no frontend release.
- **URL param**: `?variant=legacy` on any disabled-homepage URL.

Override individual feature flags the same way via bootstrap — set
`show_promo` / `show_what_is_this` to `true` / `false` / `null` (= auto).

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

Unrecognized variant ids fall back to `v1` (defense in depth — Zod
would already reject the value at parse time).

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
