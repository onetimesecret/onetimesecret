# docs/specs/qa/visual-regressions/qa-visual-regressions-approach.md

---

## Decision

Use Playwright's built-in `toHaveScreenshot()` for visual regression on customer-visible pages. Do not adopt BackstopJS. Do not adopt Storybook.

The risk you're protecting against is not component drift — it's the **domain → brand config → rendered page** pipeline breaking for B2B customers and their B2B2C recipients. That pipeline only exists in the running app, so the test has to exercise the running app. Component-level tooling can't see it.

## Why not the alternatives

**BackstopJS** now uses Playwright as its rendering engine. Adopting it means a second config format, a second baseline directory convention, and a second approval workflow wrapped around the same browser you'd run directly. Its one genuine advantage — `referenceUrl` for prod-vs-staging comparison without committed baselines — is reproducible in Playwright with two runs of the same spec (see §6). For a solo maintainer, one tool that does 100% beats two tools that overlap 90%.

**Storybook** is a parallel implementation of your UI that must be kept in sync by hand. That's a standing tax with no payoff here: stories render components with props you invent, not with brand settings resolved from a real domain record. It shines when a team needs a shared component catalog. You are the team. Defer indefinitely — but note the deferral is not a claim that component consistency doesn't matter. It's that Storybook is a *viewing* instrument for consistency, and a growing component surface calls for *enforcement* instruments (see "Component consistency" below).

## 1. Test matrix — small and fixed

The failure surface is `pages × brand configurations`, so pick representative fixtures rather than trying to cover pages exhaustively.

**Brand fixtures:**

| Fixture        | Purpose                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| `canonical`    | Default OTS branding on the primary domain                                                             |
| `branded-full` | Custom domain with primary color, logo, custom instructions, font/corner settings all set              |
| `branded-edge` | Dark primary color, long instruction text, non-English locale — the config most likely to break layout |

**Screenshot matrix** (snapshot names follow `<page>--<state>--<fixture>.png`; Playwright appends `-<projectName>-<platform>`):

| Route                       | Snapshot(s)                                          | Fixtures                   | Viewports    |
| --------------------------- | ---------------------------------------------------- | -------------------------- | ------------ |
| `/`                         | `home--default`                                      | all 3                      | both         |
| `/secret/:id`               | `secret--confirm`, `secret--revealed` (click-through), `secret--unknown` | all 3 | both         |
| `/receipt/:id`              | `receipt--fresh`                                     | all 3                      | both         |
| `/receipt/:id/burn`         | `burn--confirm`                                      | all 3                      | both         |
| `/this-page-does-not-exist` | `notfound--default`                                  | all 3                      | both         |
| `/secret/:id`               | `secret--passphrase` (confirmation w/ passphrase input) | canonical + branded-full | desktop only |
| `/receipt/:id`              | `receipt--viewed`, `receipt--burned`                 | canonical + branded-full   | desktop only |
| `/incoming`, `/incoming/:receiptId` | `incoming--form`, `incoming--success`        | canonical only             | both         |

The core rows run all 3 fixtures × both viewports (desktop 1280px, mobile 375px). The extended-state cells (passphrase, viewed, burned) are layout-stable across viewports, so desktop-only on two fixtures suffices. Incoming is canonical-only because custom-domain incoming is gated on both the `incoming_secrets` entitlement and a per-domain `IncomingConfig` — a real but deferred surface. Total: **52 baselines per platform**. Full run should stay under a couple of minutes. Resist expanding this; the value is in the branded-domain coverage, not breadth.

## 2. Simulating custom domains locally

No DNS needed. Map fixture hostnames to the app host via Chromium's resolver. Hostname choice is constrained by the app itself: the whole pipeline parses Hosts with PublicSuffix (`default_rule: nil`), so `.test`-style TLDs are rejected at both the model layer (`CustomDomain#init` raises on instantiation) and the middleware layer (`DomainStrategy` classifies them `:invalid` — no branding, ever), and the custom fixtures must live on a **different registrable domain** than the canonical host or `Chooserator.peer_of?` classifies them `:canonical` and the branded render never happens. Hence:

| Fixture        | Host                       |
| -------------- | -------------------------- |
| `canonical`    | `canonical.example.org`    |
| `branded-full` | `secrets.acme.example.com` |
| `branded-edge` | `secrets.edge.example.com` |

(`.dev` is also out — Chrome HSTS-preloads it, forcing https and breaking `http://…:7143`.)

**The server must boot with `DOMAINS_ENABLED=true` and `DEFAULT_DOMAIN=canonical.example.org`** — `site.domains.enabled` defaults to false, and when it's off the middleware classifies every Host `:canonical`, so every branded fixture silently renders the default UI: exactly the false negative this section exists to prevent. `bin/visual` exports both.

```ts
// e2e/playwright.config.ts (visual-desktop / visual-mobile projects,
// alongside the existing chromium/full/full-billing projects).
// Inside the Playwright container, 127.0.0.1 is the container itself — the
// MAP target is env-driven; bin/visual sets
// VISUAL_RESOLVER_TARGET=host.containers.internal for podman.
const resolverTarget = process.env.VISUAL_RESOLVER_TARGET ?? '127.0.0.1';

// in the project definition:
{
  name: 'visual-desktop',
  testMatch: /visual\/.*\.spec\.ts/,
  use: {
    launchOptions: {
      args: [
        `--host-resolver-rules=MAP *.example.com ${resolverTarget}, MAP *.example.org ${resolverTarget}`,
      ],
    },
    viewport: { width: 1280, height: 800 },
    reducedMotion: 'reduce',
  },
},
```

```ts
test('branded homepage', async ({ page }) => {
  await page.goto('http://secrets.acme.example.com:7143/');
  await expect(page).toHaveScreenshot('home--default--branded-full.png', {
    fullPage: true,
    maxDiffPixels: 100,
  });
});
```

Ports are not hardcoded in the specs: they derive the port (and the canonical host) from `PLAYWRIGHT_BASE_URL` (e.g. `http://canonical.example.org:7143`), so the same spec runs against any server the base URL points at. The app receives `Host: secrets.acme.example.com` and resolves the brand exactly as production would.

**Assert the brand actually rendered.** Before every branded screenshot, two guards: the `O-Domain-Strategy` response header — the middleware's own classification verdict — and one brand-specific element (logo alt text, primary-color element, custom instruction text):

```ts
const response = await page.goto('http://secrets.acme.example.com:7143/');
expect(response?.headers()['o-domain-strategy']).toBe('custom');
await expect(page.locator('[data-testid="brand-logo"]')).toBeVisible();
await expect(page).toHaveScreenshot(/* ... */);
```

Without this, a Host→brand resolution failure falls back to canonical branding and every branded screenshot silently captures the default UI — a false negative that persists: the first baseline is captured from the fallback, so all later runs compare fallback to fallback and pass. The screenshot alone cannot distinguish "brand rendered" from "fallback rendered" on the first baseline run; only an explicit assertion can.

## 3. Fixture seeding

- Seed via `bin/visual` → `rake qa:visual:seed`, **not** Playwright `globalSetup` and not per-test `beforeEach`. A config-level `globalSetup` executes for every lane — including CI's `e2e/all/` run — and would disturb suites that never asked for fixtures (a setup dependency-project was the alternative; the entrypoint won for simplicity). The brand configs are shared read-only state; the visual suite must not flush the test datastore at all — it reads, it doesn't mutate.
- Seed through the model layer (the rake task creates `CustomDomain` records + brand config via the app's own persistence code), **not** raw Redis writes. Raw writes drift from the shape the app actually produces, and the test ends up passing against data production never generates. Note: don't seed through the full domain-creation API flow either — ownership verification won't pass for the fixture hostnames; the model layer sidesteps the verification gate while keeping the persistence shape honest.
- Secret and receipt identifiers are generated-only (`Familia::VerifiableIdentifier`) — there are no "known keys" to seed. Every run mints fresh IDs, so the seed task writes a manifest at `e2e/visual/.artifacts/seed-manifest.json` (fixture hosts, per-cell secret/receipt IDs, plus a well-formed-but-nonexistent `unknownSecretId` generated without creating an object) and the specs read their URLs from it. The manifest is the contract between seed and spec.
- **One virgin record per destructive cell.** Some pages mutate state by being visited: a reveal click-through destroys the secret; the first `/receipt/:id` load stamps `receipt_viewed_at`. Cells screenshotted in both viewports therefore get one seeded record *per viewport*; metadata-only pages (the confirmation view) and terminal states (viewed, burned) safely share a single record.
- Matrix consequence worth pinning: on `/secret/:id`, **claimed, burned, and unknown are pixel-identical** — all three 404 into the UnknownSecret view. That's why the matrix has a single `secret--unknown` cell there, and the claimed/burned *visuals* live on `/receipt/:id` (`receipt--viewed`, `receipt--burned`).

## 4. Determinism rules

- `reducedMotion: 'reduce'` in config (above) kills transitions.
- `mask` anything time-relative (TTL countdowns, "expires in X hours").
- Elements rendering per-run generated identifiers (secret links, receipt IDs) are known-variable — their masks are seeded up front rather than discovered. For everything else, don't pre-engineer the mask list — grow it from real diffs.
- Generate baselines **only** inside the pinned Playwright Linux container (`mcr.microsoft.com/playwright:v1.58.2-noble` via podman — the tag must match `@playwright/test` in package.json; bump both together). Never commit darwin baselines — font rendering differs and you'll chase phantom diffs. `bin/visual` running that container keeps this honest.
- `maxDiffPixels` over `threshold` for full-page shots — it maps directly to "how much changed."

## 5. Workflow

```bash
bin/visual                         # seed, boot server, run against baselines
bin/visual --update                # after intentional UI changes (podman container; passes --update-snapshots)
git add e2e/visual/*-snapshots/    # baselines are source code
```

`bin/visual`, not `make visual`: the repo has no Makefile, and runner entrypoints live in `bin/` with an established header/guard convention. The script owns the whole lifecycle — env exports (`DOMAINS_ENABLED`, `DEFAULT_DOMAIN`, incoming config), server boot + readiness, seeding, and the pinned-container Playwright run — so no step can be skipped or run with drifted env.

CI: run the visual project on PRs touching frontend paths; upload `test-results/` as an artifact on failure so the diff images are one click away.

## 6. Immediate: gating v0.26.0

You don't need the long-term habit in place to answer this week's question. Same spec, two builds:

1. `git worktree add ../ots-v0.25 v0.25.x` — run it, seed fixtures, `--update-snapshots` against it. These baselines are "what customers see today."
2. Point the spec at your v0.26.0 build and run `npx playwright test`. Every diff in the report is a customer-visible change in the release — triage each as intentional or regression.
3. Approve the intentional ones as the new baselines and you've bootstrapped the permanent suite as a side effect of the release check.

Two operational caveats for the two-worktree run:

- Each worktree seeds through **its own tree's** rake task (the seed boots that tree's models against that tree's config). `v0.25.11` predates `qa:visual:seed`, so copy the task file into the v0.25 worktree before seeding it.
- v0.25-vs-v0.26 diffs on the branded cells will include rendering of brand fields that didn't exist in v0.25 — expected triage noise, not regression signal. Read those diffs with that in mind before blaming the pipeline.

## Component consistency — enforce, don't catalog

Screenshot tests catch pipeline breakage; they don't manage consistency across a growing component surface. Neither does a catalog: Storybook *documents* consistency, and a catalog of 150 stories drifts as fast as the components do. For a solo maintainer the sync tax and the benefit land on the same person — the economics never invert the way they do on a team where one author pays and ten consumers benefit.

Consistency is managed by making drift structurally hard, at the point of authorship:

- **Shared primitives over duplicated markup.** When a pattern appears a third time, extract it (field shells, modal/panel kits). Consistency enforced at the import site, not observed in a catalog.
- **Design tokens over literal values.** A component can't drift from a token it consumes; a hardcoded `blue-500` can. Tokenize on contact.
- **Lint and type gates in CI.** Cheap, mechanical, don't rot. Ratchet rules when a new class of drift shows up.

**When to revisit Storybook:** a second regular frontend contributor, or a design-review loop where someone non-technical needs to browse component states without running the app. Those are the team-catalog cases where the economics flip. Until one exists, catalog effort is better spent on the three levers above.

## Guardrails

Things this deliberately does not include, and shouldn't grow to include without a concrete failure motivating it: cross-browser matrix (chromium only), per-component screenshots, Percy/Chromatic SaaS, Storybook. `/feedback` is customer-visible on custom domains but consciously excluded from the matrix. The transactional email brand surface (footers, `powered_by` locale) is also out of scope — there's no Playwright page to screenshot; revisit with a separate rendered-email harness if it keeps regressing. When a customer reports a brand config that broke and wasn't covered, add it as a fourth fixture — that's the only sanctioned growth path.

One limitation to keep in mind: screenshots only catch what you screenshot. If a regression serves the _wrong_ brand entirely, the diff catches it; if it breaks a page not in the matrix, nothing does. The fixture list is the contract — keep it honest, keep it short.
