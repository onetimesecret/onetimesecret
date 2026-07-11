# Brand Manager — consumer audit report

Findings from a per-view code audit on `integration/brand-manager`, answering:
do we need to update the homepage variants (including disabled) and the
recipient page to add `secondary_color`, `heading_font`, `background_color`,
and the 8 `font_family` fonts? Constraint: we cannot add UI for a token that
has no consumer.

## Short answer

Yes — but not uniformly. "Add a consumer" is required (a token with no consumer
can't get UI), but the four tokens split into **four very different tiers of
effort**, and two of them are blocked before any view work. Also: `font_family`
already renders on the recipient page, so "the 8 fonts" aren't uniformly missing.

## Where each token stands today (verified per-view)

| Token | Recipient page | Homepage (`BrandedHomepage`) | Disabled variants | Verdict |
|---|---|---|---|---|
| **`font_family` (8 fonts)** | ✅ **renders** (`fontClass` on h2/p/button; all 8 stacks defined in `style.css`) | ❌ no font class at all | ❌ uses *fixed* `font-brand` (our Zilla Slab), not the domain font | Recipient done; homepage/disabled don't apply it |
| **`heading_font`** | ❌ (h2 uses body font) | ❌ (h1 hardcoded) | ❌ | **Cleanest to wire.** Zero consumers anywhere |
| **`secondary_color`** | ❌ — *no element maps to a secondary role* (every accent is `primary`) | ❌ same | ❌ same | **Needs a design decision** (what does it even color?) before a consumer exists |
| **`background_color`** | ❌ hardcoded `bg-white dark:bg-gray-800` | ❌ surface is body-owned + card over-paints | ❌ | **Blocked on supply side** (below) |

`text_color` is folded in because it's `background_color`'s inseparable pair —
you can't brand a background without branding the ink on it.

## The one blocker that changes the sequencing

`--color-brandbg` (`#ffffff`) and `--color-brandtext` (`#1f2937`) are
**single-value, light-only** tokens with **no dark-mode pair**
(`style.css:125-126`). These pages support dark mode and the theme toggle is
*not* disabled for custom domains. So dropping `bg-brandbg`/`text-brandtext` in
place of the existing `text-gray-900 dark:text-white` pairs yields a **white
block / unreadable ink in dark mode**. `background_color`/`text_color` are not a
class swap — they need a supply-side dark-mode story first (derive a dark pair,
or force branded surfaces light).

## Disabled-page observation — confirmed, with root cause

Corners and font are ignored on **all three** disabled variants because
**`useDisabledConfig.ts` never exposes `cornerClass` or `fontFamilyClass`** (its
props bag is only `primaryColor`/`logoUri`/`displayName`/…). So the variants
*structurally can't* honor them — they hardcode `rounded-xl/2xl/3xl/full` and the
fixed product `font-brand`. Worse, the **default** variant (`closed`) discards
the props bag entirely and delegates to `DisabledHomepageTaglines`, so it
consumes *zero* brand tokens. Rendering the domain font there is arguably a
**bug** (it shows *our* font on someone else's branded domain), separate from the
new-token work.

## Recommendation (ordered by readiness)

1. **`heading_font` → wire now.** Add a `headingClass` prop to
   `BaseSecretDisplay` (recipient h2) and `:class="headingFontClass"` on
   `BrandedHomepage` h1. Cheap, unblocked, then safe to add its Simple-path UI.
   This is the one token ready to earn a control.
2. **`font_family` on disabled → fix as a bug.** Add `fontFamilyClass` (and
   `cornerClass`) to `useDisabledConfig`'s props bag, drop the hardcoded
   `font-brand`. No new UI needed — the `<select>` already exists.
3. **`secondary_color` → do *not* add UI yet.** No view has a slot for it; every
   accent is already `primary`. Decide what it styles first — that's design, not
   wiring.
4. **`background_color`/`text_color` → do *not* add UI yet.** Blocked on the
   single-value-vs-dark-mode issue above. Needs a supply-side decision before any
   view or control.

So: update the recipient page + homepage for **`heading_font`**, fix the disabled
page's **font/corners** plumbing, and **hold** `secondary_color` and
`background_color` behind a design and a dark-mode decision respectively.

## Per-view detail (verified, with attach points and blockers)

### Homepage variants (secret-creation landing on a custom domain)

Group receives per-domain brand on its one branded surface, `BrandedHomepage.vue`
(`isCustom`→custom, `identityStore.ts:193`; `useBrandTheme` injects `<html>`
vars). None of the five tokens is consumed in any of the three files (the only
brand consumption is out-of-set: `primaryColor`/`brand-500`, `cornerClass`,
`buttonTextLight`, `logoUri`).

- **`src/apps/secret/conceal/Homepage.vue`** — Pure dispatcher/wrapper. Renders
  no text, headings, surfaces, or brand tokens of its own. Any token attached
  here styles both the branded and non-branded child indiscriminately; the
  correct home is the leaf view, not this dispatcher.
- **`src/apps/secret/conceal/BrandedHomepage.vue`** — THE branded custom-domain
  landing (the only file a real custom domain renders).
  - `font_family`: not consumed. Root wrapper div (line 109) → add
    `:class="fontFamilyClass"` (must import from identityStore) to set body copy
    font via inheritance. But base rules for button/`a.block` and h1..h5
    (`style.css:212-224`) keep Zilla Slab on the SecretForm button and headings
    unless those elements are individually classed — PARTIAL coverage only.
  - `heading_font`: not consumed. The `<h1>` at line 122 → add
    `:class="headingFontClass"` (import from identityStore). `identityStore.ts:317-318`
    explicitly names BrandedHomepage as the intended activation target. The
    utilities-layer `font-brand-*` overrides the base-layer h1 rule, so this works.
  - `secondary_color`: not consumed. No element maps to secondary today. Every
    accent is PRIMARY: accent bar `bg-brand-500` (186), icon chip `bg-brand-500/10`
    (191), icon `text-brand-500` (195). Binding `brand2-*` is net-new design, not
    an audit drop-in.
  - `background_color`: not consumed, and no clean per-view home. `bg-brandbg` on
    the `max-w-xl` wrapper (line 109) paints only the centered column, not the
    viewport; a real surface swap belongs on BaseLayout root `.min-h-screen` div
    (`BaseLayout.vue:44`) or the backend `<body>`, neither of which is per-view.
    Hardcoded surfaces paint over any ancestor `bg-brandbg` anyway: trust card
    `bg-white dark:bg-gray-800` (184), feature pills `bg-gray-50 dark:bg-white/5`
    (207, 217).
  - `text_color`: not consumed. Replace hardcoded grays with `text-brandtext`: h1
    line 122 (`text-gray-900 dark:text-white`), subline line 125
    (`text-gray-600 dark:text-gray-300`), trust-card copy line 198, pill labels
    212 & 222. A single root-level `text-brandtext` will NOT work — every child's
    explicit `text-gray-*`/`dark:text-*` overrides it.
  - BLOCKER (both bg + text): single-value token vs dark mode. `brandbg=#ffffff`
    and `brandtext=#1f2937` (`style.css:125-126`) have no light/dark pair; this
    surface supports dark mode (`useTheme.ts` toggles `.dark` on `<html>`,
    `displayToggles` defaults true), so the swap is unreadable/white-block in dark.
- **`src/apps/secret/conceal/HomepageContent.vue`** — Canonical/subdomain
  (NON-custom) homepage. OFF-PATH: a custom domain always routes to
  BrandedHomepage (`Homepage.vue:33`), so tokens applied here only ever show
  `@theme` defaults on canonical. No token-bearing elements in this file —
  headings/body text live in child components (HomepageTaglines, SecretForm).

### Disabled homepage variants (secret creation disabled for the domain)

Dispatched by `DisabledHomepage.vue` via the VARIANTS map; default variant is
`closed`. The group receives brand — `primaryColor`, `logoUri`,
`isBranded`/`workspaceName`/`monogramInitial` flow through the `useDisabledConfig`
props bag — but NONE of the 5 audited tokens has a live attach point in any
variant. The `primaryColor` that IS consumed (monogram/dot `backgroundColor`) is
the PRIMARY brand color, a DIFFERENT token from the audited `secondary_color`
(→ `--color-brand2-*`, zero consumers here). Two distinct blocker mechanisms:
`font_family`/`heading_font` are blocked by the props-bag gap (class strings are
domain-derived, only reachable via identityStore, and `useDisabledConfig` does not
expose `fontFamilyClass`/`headingFontClass`); `background_color`/`text_color`/
`secondary_color` are NOT props-blocked (they resolve off `<html>` as plain
utilities) but hit the dark-mode / per-element / no-slot issues.

- **`DisabledV1.vue`** — Full "composed refresh" hero.
  - `font_family`: not consumed. Root wrapper (line 48) → `:class="fontFamilyClass"`,
    but each text child carries its own font utility that wins by source order, so
    realistically per-element (h1:90 uses `font-brand`, subtitle p:115, CTA buttons
    132/148 use `font-sans`).
  - `heading_font`: not consumed. `<h1>` (90-91) → add `:class="headingFontClass"`
    AND remove the hardcoded `font-brand` (two font-family utilities on one element
    resolve by CSS source order, so `font-brand` must go).
  - `secondary_color`: not consumed. Candidate accent slots: eyebrow dot (78-80,
    today driven by inline `dotStyle`/`primaryColor`) or promo accent chip (196,
    today `brandcomp-500`) → could become `bg-brand2-500`/`text-brand2-600`.
    Adoption is a design choice.
  - `background_color`: not consumed. Root wrapper (48) → `bg-brandbg`; OR better at
    the layout root (`BaseLayout.vue:44`, owns no bg today). Page background is
    body-owned, not per-view.
  - `text_color`: not consumed. Per-element replace: h1 (91), subtitle (115),
    "what is this" (160), trust strip (174,181), promo (203,206) → `text-brandtext`.
    Root-level won't cascade over the hardcoded `text-gray-*`/`dark:text-*`.
  - BLOCKERS: props-bag gap (no `fontFamilyClass`/`headingFontClass`); hardcoded
    `font-brand` on h1 (90)/monogram (60) competes by source order; per-element
    hardcoded text colors override root `text-brandtext`; `brandbg`/`brandtext`
    single-value → wrong in dark mode.
- **`DisabledMinimal.vue`** — Quiet single-column variant.
  - `font_family`: not consumed. Root wrapper (37) → `:class="fontFamilyClass"`;
    h1 (64) for its own font. Same source-order caveat.
  - `heading_font`: not consumed. `<h1>` (64) → `:class="headingFontClass"`, remove
    hardcoded `font-brand`.
  - `secondary_color`: not consumed. Monogram (33 inline `primaryColor`) and focus
    rings (105,121 `brand-500`) already claim the accent role.
  - `background_color`: not consumed. Root wrapper (37) → `bg-brandbg`, or layout
    root. Variant owns no surface color.
  - `text_color`: not consumed. Per-element: h1 (64), subtitle (88), CTA (105,121),
    "what is this" (133) → `text-brandtext`.
  - BLOCKERS: same props-bag gap; hardcoded `font-brand` (64/49) source-order;
    CTA surfaces `bg-white dark:bg-gray-900` (105,121) fight `brandbg`; single-value
    tokens wrong in dark mode.
- **`DisabledClosed.vue`** — DEFAULT variant
  (`DEFAULT_DISABLED_HOMEPAGE_VARIANT = 'closed'`). Deliberately dumb: discards the
  props bag (`_props` line 21, unused) and delegates entirely to
  `DisabledHomepageTaglines` (two i18n taglines). The least brand-aware surface,
  and the one shown by default.
  - The ONLY in-file attach point of any of the 5 tokens is `bg-brandbg` on the
    root wrapper (line 25). All font/text attach points are in the out-of-scope
    child `DisabledHomepageTaglines.vue` (its h1 line 19 — which does NOT use
    `font-brand` — and p line 22, both hardcode grays).
  - BLOCKER: because `closed` is the DEFAULT, the default disabled homepage consumes
    zero of all five tokens; wiring means editing the out-of-scope child or
    abandoning the "ignores props" contract.
- **`useDisabledConfig.ts`** — The composition root / supply wiring. Props bag
  (251-266) exposes `primaryColor`/`logoUri`/`isBranded`/etc. but NO
  `fontFamilyClass`/`headingFontClass`.
  - `font_family` first step: add `get fontFamilyClass() { return identityStore.fontFamilyClass; }`,
    extend `DisabledHomepageProps` (58-91), then variants apply it.
  - `heading_font` first step: add `get headingFontClass() { return identityStore.headingFontClass; }`,
    extend `DisabledHomepageProps`, then attach in variant `<h1>`s.
  - `secondary_color`/`background_color`/`text_color`: N/A here — consumed via the
    `<html>`-injected `bg-brand2-*`/`bg-brandbg`/`text-brandtext` utilities applied
    directly in templates; must NOT be wired through this composable.

### Recipient page (branded reveal — what the secret recipient sees)

- **`src/apps/secret/reveal/branded/ShowSecret.vue`** — Branded reveal
  container/orchestrator. Owns only slot-wrapper divs; delegates all token
  rendering to children. Reads `brandSettings = productIdentity.brand` as a
  NON-reactive snapshot (line 33). No token applied at this level.
- **`src/apps/secret/reveal/branded/UnknownSecret.vue`** — Branded "secret not
  found / viewed or expired" view.
  - `font_family`: CONSUMED. h2 title (50-52) via
    `fontFamilyClasses[brandSettings.font_family]`; also BaseUnknownSecret root
    wrapper. Message `<p>` (61) and action `<router-link>` (74) do NOT get it and
    could.
  - `heading_font`: not consumed. The `<h2>` (48) → add
    `:class="productIdentity.headingFontClass"` (currently receives fontFamilyClass
    at 50-52). No productIdentity access here (prop-driven); needs a store import or
    new prop.
  - `secondary_color`: speculative — icon container (27, currently `bg-brand-500/10`)
    could take a brand2 accent.
  - `background_color`: `BaseUnknownSecret` root card (`BaseUnknownSecret.vue:22`)
    hardcodes `bg-white dark:bg-gray-800` → swap to `bg-brandbg`. Editing that shared
    base also affects the canonical (unbranded) UnknownSecret.
  - `text_color`: h2 (49, `text-gray-900 dark:text-white`) and message `<p>` (61)
    fight `text_color`; each element must get `text-brandtext`.
  - BLOCKER: `font_family` rides the non-reactive `brandSettings` snapshot
    (`ShowSecret.vue:33`); brand arriving post-mount may not be reflected.
- **`src/apps/secret/components/branded/BaseSecretDisplay.vue`** — Shared inner card
  scaffold used by BOTH confirmation and reveal states. Receives `cornerClass` +
  `fontClass` props (no heading prop).
  - `font_family`: CONSUMED. `fontClass` on h2 (102), instructions `<p>` (113),
    show-more `<button>` (121).
  - `heading_font`: not consumed. h2 (101-102) → bind a new `headingClass` prop.
    This h2 is the ONLY reveal-page heading (the card title) and is the correct
    in-route attach point. Activating it requires a prop-thread from both parents.
  - `secondary_color`: speculative — footer "careful, only see once" marker (155)
    could carry a brand2 accent.
  - `background_color`: root card (94) hardcodes `bg-white dark:bg-gray-800`; content
    well (143) `bg-gray-100 dark:bg-gray-700` → the root would take `bg-brandbg`.
  - `text_color`: h2 (104), instructions (textClasses line 59), footer (154) → each
    must get `text-brandtext`.
  - BLOCKER: no `headingClass` prop; only `cornerClass` + `fontClass` are passed.
    bg/text have no dark-mode pair on the supply side while this card is authored as
    light/dark pairs — consuming the brand utilities means brand wins in both themes.
- **`src/apps/secret/components/branded/SecretDisplayCase.vue`** — Revealed-secret
  card. Uses productIdentity computed refs directly.
  - `font_family`: CONSUMED. Passes `:font-class="fontFamilyClass"` to
    BaseSecretDisplay (84); also on the copy button (194).
  - `heading_font`: no own heading (title from BaseSecretDisplay h2). Would pass a
    new `:heading-class="productIdentity.headingFontClass"`.
  - `secondary_color`: speculative — success/error alert (37-43, `brand-*`/`branddim-*`).
  - `background_color`: own surfaces hardcoded (content well 169
    `bg-gray-100 dark:bg-gray-800`, logo tile 136).
  - `text_color`: textarea (177, `dark:text-white`) and lock-icon (142) fight it;
    copy-button text is `buttonTextLight`-driven (196).
- **`src/apps/secret/components/branded/SecretConfirmationForm.vue`** —
  Passphrase-entry / confirmation card. Uses productIdentity computed refs directly.
  - `font_family`: CONSUMED. Passes `:font-class="fontFamilyClass"` to
    BaseSecretDisplay (74); also on the submit button (178).
  - `heading_font`: no own heading (title from BaseSecretDisplay h2). Would pass a
    new `:heading-class="productIdentity.headingFontClass"`.
  - `secondary_color`: speculative — passphrase input focus ring (164).
  - `background_color`: own surface hardcoded (logo placeholder 82).
  - `text_color`: content-status text (115) and passphrase input (164) fight it;
    submit-button text is `buttonTextLight`-driven (179).
  - Aside (not a token finding): `logoImage` (65) uses `/imagine/${domainId}/logo.png`,
    the 404-prone path `SecretDisplayCase:70-73` explicitly warns against.
- **`src/apps/secret/components/layout/BrandedMastHead.vue`** — Branded masthead
  (logo tile + h1 + subtext + optional Sign In/Up). NOTE: NOT rendered on the
  recipient reveal route — `secret.ts:68` sets `displayMasthead:false` and
  `BrandedHeader.vue:50` gates on `v-if="displayMasthead"`. It renders on the branded
  HOMEPAGE, not to the secret recipient.
  - `font_family`: CONSUMED. On the content wrapper (156) and `<h1>` (161) via
    `productIdentity.fontFamilyClass`.
  - `heading_font`: `<h1>` (159-161) → add/swap `:class="productIdentity.headingFontClass"`
    (currently gets fontFamilyClass at 161). Lowest-friction activation point; the
    store is already imported and `identityStore:318` names this file family as the
    intended target.
  - `secondary_color`: speculative — nav separator (99) or signin/signup links.
  - `background_color`: root band (81) `bg-white dark:bg-gray-900`; logo tile (126) →
    root band would take `bg-brandbg`.
  - `text_color`: h1 (160), subtext (165), nav links (93,109) each fight it.
  - BLOCKER: OFF-ROUTE for the recipient — `displayMasthead:false` on
    `/secret/:secretIdentifier` (`secret.ts:68`) means any `heading_font` activated
    on its `<h1>` shows nothing to the recipient; it only appears on the branded
    homepage.
