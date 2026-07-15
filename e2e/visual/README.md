# e2e/visual/README.md

---

# Visual regression — quick reference

Details: `docs/specs/qa/visual-regressions/qa-visual-regressions-approach.md` and `bin/visual --help`.

## Check the current tree against the committed baselines

```bash
pnpm run build
bin/visual
pnpm exec playwright show-report e2e/playwright-report   # only if it failed
```

## Compare the current tree against a released version

```bash
pnpm run build
oras pull ghcr.io/onetimesecret/onetimesecret/visual-baselines:v0.25.11 \
  -o e2e/visual/.artifacts/v0.25.11
bin/visual --compare e2e/visual/.artifacts/v0.25.11
pnpm exec playwright show-report e2e/playwright-report
```

In the report, open a failure and use the **Slider** tab. Every diff is a
customer-visible change between that release and your tree.

## Update the committed baselines (after an intentional UI change)

```bash
pnpm run build
bin/visual --update
git add e2e/visual/*-snapshots/
```
