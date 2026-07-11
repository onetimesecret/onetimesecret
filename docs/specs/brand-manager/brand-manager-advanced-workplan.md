# Advanced Branding — Implementation Work Plan (final, critique-revised)

> Status: planning-final. Companion to `docs/specs/brand-manager/brand-manager.md`, `brand-manager-advanced.md`, `brand-manager-report.md`.

## Approach recap

The Advanced path is a runtime token-override editor, not a compile pipeline. Tailwind v4's `@theme static` block (src/assets/style.css:31-144) emits every `--color-brand*`/`--radius-brand`/`--font-brand-*` variable to `:root` unconditionally, and `useBrandTheme` (src/shared/composables/useBrandTheme.ts, activated once in App.vue:18) already overrides them at runtime as inline styles on `<html>` — the 44-key primary palette plus the #3646 extended tokens (`--color-brand2-*` from secondary_color, `--color-brandbg`, `--color-brandtext`, `--radius-brand`). Advanced writes validated values into the EXISTING typed BrandSettings fields (secondary_color, background_color, text_color, heading_font, full-range border_radius — src/schemas/contracts/custom-domain/brand-config.ts:153-262; accepted server-side via the BrandSettings.members slice, apps/api/domains/logic/domains/update_domain_brand.rb:59-62) and lets the same injection channel apply them.

**Non-goals (unchanged):** no runtime compilation of new utilities or `@theme` blocks (brand-manager-advanced.md:30), no new token vocabulary, no theme presets (brand-manager.md:148-157), no exception to the closed allowlist — no custom CSS, no free-form fonts (brand-manager.md:216-223, 328-331).

**Discipline (unchanged):** never ship a control for a token with no renderer.

## Verified constraints (critical facts this plan rests on)

- **Working tree, not committed history, carries the consumer wiring.** `git status`: 10 modified unstaged files, +89/−20 — BaseSecretDisplay.vue (headingClass at :15,33,105 — absent from HEAD), SecretDisplayCase.vue, SecretConfirmationForm.vue, BrandedHomepage.vue:124, useDisabledConfig.ts:72,78,294-296 (fontFamilyClass/cornerClass, NOT headingFontClass), DisabledV1.vue, DisabledMinimal.vue, SecretPreview.vue:84-123, identityStore.ts, brand-helpers.ts. C1 must commit all ten.
- **The substrate is not on main.** origin/main has no `src/apps/workspace/components/dashboard/brand/` directory (verified `git ls-tree` empty); origin/main's brand_settings.rb contains zero occurrences of secondary_color/heading_font/border_radius; the branch is 21 commits / 64 files / +3240−1404 ahead; PR #3694 merged into integration/brand-manager, not main; no open PR bridges to main. Hence the PR model below and new chunk C14.
- **Save pipeline is clean:** brandStore.ts:37-66 PUTs the record unfiltered and parses v3; the isEqual dirty-check whitelist (brandStore.ts:126-141) includes all five extended fields.
- **updateDomainBrandRequestSchema is NOT dead:** its type `UpdateDomainBrandRequest` is consumed at src/shared/stores/domainsStore.ts:5,90,316 and mocked in three test files. Type-only consumption → the v2 shape rejects extended fields at compile time only (never `.parse()`d in the save path); retarget, don't delete.
- **Backend contract (integration lineage only):** update_domain_brand.rb:59-62 members-slice allowlist; :126-131 uniform custom_branding gate; brand_settings.rb:287-303 heading_font/border_radius validators (RADIUS_MAX=64), :347-365 hex normalization, :147-155 contrast-never-blocks-save.
- **Pairwise contrast helper already exists:** `contrastRatio(hex1, hex2)` exported at src/utils/brand-palette.ts:390 (Ruby twin brand_settings.rb:374); only the advisory UI is unbuilt (dead key low_contrast_text_bg_warning, workspace-branding.json:181).
- **BaseSecretDisplay is props-only** (BaseSecretDisplay.vue:29-37) and is rendered by SecretPreview from the EDITED record (SecretPreview.vue:115-123; BrandPreviewColumn.vue:15-18 documents 'everything derives from brandSettings inline'). Any set-vs-unset conditional inside it must derive from props.domainBranding, not identityStore.
- **Unknown-secret surfaces are legacy-only:** BaseUnknownSecret.vue:25-26 honors only `corner_style==='square'` + font_family; branded ShowSecret.vue:61-64 is a corner_style-only class map. Consumers: UnknownSecret.vue, UnknownReceipt.vue — recipient-facing.
- **Injection/preview mechanics:** useBrandTheme.ts:36-41 EXTENDED_KEYS registration (+ clearOverrides :80-85); :110-112 `<html>` vars carry the operator's theme, not the edited domain; :129-135 brand2 scale injection; :139-140 setOrClear; :196-202 single-entry injection (editor must never write documentElement). SecretPreview.vue:99-104 is the locally-scoped `--radius-brand` precedent. style.css:125-126: brandbg/brandtext are single-value light-only. tailwind-safelist.ts:43-56: brandbg/brandtext/brand2 utilities safelisted; zero .vue consumers today.

## PR model

All Wave 1-2 chunk PRs target **integration/brand-manager**. C14 lands integration→main after C12a browser-verifies both Advanced v1 and the (never browser-verified) three-path rebuild. Wave 3 chunk PRs target **main** post-C14. Each chunk is one landable PR; C5a/C5b (hash runs) must be their own PRs.

## Chunks

### Wave 1 — Foundation (parallel, independently landable to integration)

**C1 — Commit and land the full consumer wiring** (0.5d, no deps)
Commit ALL 10 modified working-tree files — the wiring itself is the payload, not a brand-helpers.ts comment edit. Re-baseline brand-manager-report.md (its root-cause claim at :39-49 is stale vs useDisabledConfig.ts:190-196,280-281). Note: the disabled-variant diff wires fontFamilyClass/cornerClass only, not headingFontClass — C11 remains distinct. Run BrandEditor.spec.ts + branded specs; PR to integration/brand-manager; browser spot-check heading_font on homepage h1 and recipient h2.

**C2 — Schema hygiene** (0.5d, no deps)
Retarget updateDomainBrandRequestSchema (src/schemas/api/domains/requests/update-domain-brand.ts:9-14) to brandSettingsCanonical.partial() — deletion is off the table (domainsStore.updateDomainBrand consumes the type; three test files mock it; all now in the file list). Audit canonical/v2 response consumers (api/domains/responses/domains.ts:39 drops extended fields on parse); retarget brand-bearing ones to v3 or deprecation-comment. Round-trip vitest for all five fields.

**C3 — Backend API round-trip tryouts** (0.5d, no deps)
No backend code changes needed on the integration lineage (premise does NOT hold on main — another reason C14 precedes Wave 3). Tryout cases: hex normalization (3/6-digit → 6-digit uppercase), heading_font enum accept/reject, border_radius presets + 0/64 accept + 65/negative reject, GET returns saved values via safe_dump, unknown-key discard, and a case pinning corner_style + border_radius coexistence pending **Q4** (draft mis-cited Q7). Run `try --agent`.

### Wave 2 — First shippable Advanced path (on integration)

**C4 — Advanced panel v1: heading font + full-range border radius** (1.5d, deps: C1 — the C2 gate was artificial and is dropped)
Replace the teaser with AdvancedBrandPanel: heading_font (8-value enum select; identityStore.headingFontClass renders it; null = inherit body font) and border_radius full range (6 presets + 0-64px numeric, isValidBorderRadius pre-emit with inline error). Same contract as SimpleBrandPanel (immutable spread emits, SimpleBrandPanel.vue:46-48); never touch corner_style; never bypass the store (single Save, DomainBrand.vue:116). Flip paths.ts:18 available:true; delete BrandAdvancedTeaser.vue. **i18n content edits live here** (feature-PR review, not buried in hash noise): delete coming_soon_advanced_blurb (workspace-branding.json:262, consumed at BrandEditor.vue:72), reword path_advanced_tag (Q7), add new keys as bare `{"text": ...}` — hashes in C5a.

**C11 — Disabled-variant completion: headingFontClass** (0.5d, deps: C1, parallel with C4)
Add headingFontClass to DisabledHomepageProps (useDisabledConfig.ts:72-78) following the null-when-no-explicit-choice convention; consume on DisabledV1.vue:92 / DisabledMinimal.vue:66 h1s as `headingFontClass ?? fontFamilyClass ?? 'font-brand'`. DisabledClosed untouched pending Q5.

**C13 — Unknown-secret surfaces migration** (0.5d, deps: C1, parallel with C4) *(new — closes a consumer family the draft missed)*
BaseUnknownSecret.vue:25-26 and the branded ShowSecret wrapper (ShowSecret.vue:61-64) honor only legacy corner_style (+font_family) — no border_radius, no heading_font — yet render the expired/burned/unknown-link pages (UnknownSecret.vue, UnknownReceipt.vue). Migrate both to the cornerClass derivation (border_radius supersedes) + heading-font ladder, or the 'zero silent no-ops' bar fails the day C4 ships. Background/text-color wiring for these surfaces is Q1-gated and rides with C6. ShowSecret.vue:33's non-reactive snapshot stays Q8 — distinct defect, not fixed here.

**C5a — locales:hashes run, Wave 2** (0.5d, deps: C4, C11, C13)
PURE hash pass, own PR (the ~2000-hash tree-wide rewrite must not bury content edits — those moved to C4). Record (don't implement) the borderRadiusDisplayMap/fontDisplayMap i18n-ization decision.

**C12a — Browser verification, Wave 2** (0.5d, deps: C4, C5a, C11, C13)
Verifies Advanced v1 AND the three-path rebuild itself (shipped browser-unverified per #3694 history). Editor smoke (path switch, Save persistence, save-failure rollback UX per useBranding.ts:201-212); heading_font + non-preset radius (e.g. 22px) across homepage h1, recipient h2, unknown-secret pages, disabled variants; Simple's 3-corner buttons tolerate non-preset values. Sign-off gates C14. This split also fixes the draft's contradiction: under a Q1/Q2 stall, Wave 2 no longer ships unverified.

### Gate — landing on main

**C14 — Land integration/brand-manager on main** (1d, deps: C12a, C2, C3) *(new — the merge the draft never scheduled)*
Open and shepherd the integration→main PR (21+ commits, 64+ files, +3240/−1404 plus Wave 1-2 work) with real review budget and C12a screenshots attached. Resolve main-drift (BrandSettingsBar.vue exists on main, deleted on branch). Full CI. Wave 3 rebases onto main after merge. Reviewer/timing = **Q9**.

### Wave 3 — Color expansion (decision-gated, targets main)

**C6 — Dark-mode resolution + background/text color consumers** (1.5d, deps: C14; GATED on Q1)
brandbg/brandtext are single-value light-only tokens (style.css:125-126) vs a live theme toggle. Recommended: operator-explicit values win both schemes — conditional class swap to `bg-brandbg`/`text-brandtext` without `dark:` when set; unset domains pixel-identical. **Placement fix vs draft:** BaseSecretDisplay's swap derives from **props.domainBranding** in a local computed (props-only component, reused by SecretPreview for the EDITED record — an identityStore conditional would key preview set-ness on the wrong domain); the identityStore computed (hasSurfaceColors/brandSurfaceClasses, mirroring cornerClass at identityStore.ts:296-307) serves only store-reading surfaces (BrandedHomepage). Wire: BaseSecretDisplay :62,:97,:107,:145-146; BrandedHomepage h1 :125, subline :128, trust-card text AND background :187 (draft wired text only — homepage had zero background surface); SecretForm card :152 = Q1b sub-decision; extend C13's unknown-secret surfaces with the same prop-derived swap. If Q1 → derived-dark-pair instead: new tokens must register in EXTENDED_KEYS + clearOverrides (useBrandTheme.ts:41,80-85) or they leak past dispose. No new safelist entries (tailwind-safelist.ts:43-50 covers these; template classes static).

**C7 — Advanced panel v2: background/text controls + contrast advisory** (0.5d, deps: C4, C6)
Two ColorPickers with explicit clear-to-default (null → override removed → @theme default, setOrClear useBrandTheme.ts:139-140). Advisory = `contrastRatio(text_color, background_color) < 4.5` — the helper ALREADY EXISTS (brand-palette.ts:390); only the advisory computed + wiring of the dead low_contrast_text_bg_warning key is new (hence 0.5d, down from 1d). Advisory-only, never blocks save (brand_settings.rb:147-155). button_text_light watcher keys on primary_color only (useBranding.ts:148-158) — no collision; document it.

**C8 — secondary_color: role + consumers + control, one atomic PR** (1.5d, deps: C4, C14; GATED on Q2) *(absorbs draft C9)*
Decide the secondary role (candidates: DisabledV1 eyebrow dot/promo chip, BaseSecretDisplay footer marker, alert accents — no view has a secondary slot today), wire static brand2 utilities preserving dark-mode scale relationships (`text-brand2-600 dark:text-brand2-400`), AND add the ColorPicker with seed-color semantics (one hex → 11-shade scale; never per-shade editing) in the same PR — renderer + control land together, so the PR is user-visible and 'never a control without a renderer' holds atomically. Slate @theme defaults keep unset domains stable. Safelist extended only for shades outside the curated subset. No neutral-gating, deliberately (useBrandTheme.ts:122-127).

**C10 — Preview fidelity** (0.5d, deps: C6, C8)
Extend SecretPreview's locally-scoped var precedent (SecretPreview.vue:99-104): set `--color-brandbg`, `--color-brandtext`, and the 11 `--color-brand2-*` keys (generateNamedScale) on rootStyle when present. Reduced from 1d: C6's prop-derived swap makes the conditional-class half preview-correct for free; this is var injection only. NEVER write documentElement from the editor (useBrandTheme.ts:196-202). Optionally surface the secondary accent in BrandPreviewColumn per C8's role.

**C5b — locales:hashes run, Wave 3** (0.5d, deps: C7, C8) *(new — draft scheduled the pass once, stranding Wave 3 keys hash-less)*
Pure hash pass for C7/C8 keys, own PR.

**C12b — Browser verification, Wave 3** (1d, deps: C6, C7, C8, C10, C5b)
Colors in light AND dark (the core Q1 risk); unset domains pixel-identical; preview-vs-recipient parity including the cross-domain case (editing domain B while operator's domain has no colors — the C6 regression case); known-gap spot checks (DisabledClosed until Q5; ShowSecret Q8 snapshot).

## Dependency graph and sequencing

```
Wave 1:   C1        C2        C3          (parallel, → integration)
           │
Wave 2:   C4(←C1)   C11(←C1)  C13(←C1)    (parallel, → integration)
           └────┬──────┴─────────┘
              C5a → C12a
                      │
Gate:               C14 (←C12a,C2,C3)      (integration → main)
                      │
Wave 3:   C6(←C14,Q1) ──→ C7(←C4,C6)
          C8(←C4,C14,Q2)
          C6+C8 → C10;   C7+C8 → C5b
                      │
Close:              C12b (←C6,C7,C8,C10,C5b)
```

- Critical path: C1 → C4 → C12a → C14 → C6 → C7/C10 → C12b ≈ 7 days.
- Q1/Q2 stall contingency: Waves 1-2 + C14 ship a complete, **browser-verified** Advanced v1 (heading font + full-range radius, covering homepage, reveal, unknown-secret, and disabled surfaces) to main in ~6 days.
- **Totals: ≈ 11.5-12 days** (Wave 1: 1.5d; Wave 2: 3.5d; gate: 1d; Wave 3: 5.5d). Growth over the draft's 10-11d is exactly the critique-mandated additions: C13 (unknown-secret surfaces, 0.5d) + C14 (main merge, 1d) + C5b (0.5d), partly offset by reductions in C7 (helper exists) and C10 (prop-derived swap).

## Open questions (need product/owner decision — do not resolve silently)

1. **Q1 (blocks C6/C7): dark-mode strategy for background_color/text_color.** Single-value light-only tokens (style.css:125-126) vs live theme toggle: operator value wins both schemes and operator background applies to the BrandedHomepage SecretForm card (:152).

2. **Q2 (blocks C8): what does secondary_color style?** No view has a secondary slot (brand-manager-report.md:22,61-62). Design decision before wiring.

3. **Q3: teaser affordances.** Cut both 'Copy tokens' and 'Import .css' from v1 — importing means parsing untrusted CSS, forbidden by the allowlist constraint (brand-manager.md:216-223, 328-331).
4. **Q4: should saving border_radius clear legacy corner_style?** Coexistence is safe (frontend precedence); C3 pins current behavior either way.
5. **Q5: DisabledClosed** (default disabled variant) consumes zero brand tokens (DisabledClosed.vue:21). Wire, flip default, or accept the gap?
6. **Q6: Advanced-specific entitlement?** Recommend no — custom_branding gates the whole hash uniformly (update_domain_brand.rb:126-131).
7. **Q7: path_advanced_tag replacement copy** — reworded mechanically in C4, wording is a product-voice call.
8. **Q8: ShowSecret.vue:33 non-reactive brand snapshot** — separate fix, pre-existing (distinct from the :61-64 class map C13 migrates).
9. **Q9 (new, blocks C14 timing): who reviews the integration→main merge, and when?** Recommended: after C12a (the rebuild has never been browser-verified; main has drifted).
