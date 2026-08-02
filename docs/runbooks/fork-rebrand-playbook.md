# Playbook: Converting a Customized Fork to Brand-Pack Configuration

Migrate a fork with hardcoded branding (pre-v0.26 style) onto the official
brand-pack system (v0.26.2+, #3739/#3774).

## 1. Enumerate the fork's delta

Find the last upstream merge point and diff against it:

```bash
git merge-base <fork-branch> upstream/main        # or inspect the merge commit's 2nd parent
git tag --contains <merge-base>                   # confirm which upstream version it maps to
git diff --name-only <merge-base>..<fork-branch>
```

Classify each changed file:

- **Branding** — logos, favicons, colors, component edits (DefaultLogo.vue,
  DisabledMinimal.vue, style.css palette, test hex literals).
- **Deployment** — `.oci-build.json`, registry config. Keep as fork commits.
- **Noise** — version bumps, prettier reformatting, notes docs. Drop.

## 2. Extract brand facts

From the fork branch (via `git show <branch>:<path>`, no checkout needed):

- Primary color hex (check `.interface-design/system.md`, test literals, CSS).
- Logo assets: wordmark SVG(s), light/dark variants, fills.
- `favicon.ico` and any other replaced icons.
- Product name / site title / TOTP issuer / support email — often set via
  `BRAND_*` env in the deployment, not in the repo; check relevant
  correspondence docs if present.

## 3. Check coverage, note gaps

Map each customization onto the v0.26.2+ config surface (`BRAND_*` env vars,
pack `brand.yaml`, pack asset files — see upstream
`docs/architecture/branding.md` and `docs/product/branding-favicon.md`).
Known gaps to watch for (record as memory / follow-up, don't block):

- **Dark-mode logo variant** — upstream has a single `logo_url`; forks with
  separate light/dark logos need one dual-background SVG or an upstream patch.
- **Suppressing the logo entirely** on specific views (e.g. disabled
  homepage) — no config knob.

## 4. Build the pack on a clean upstream base

```bash
git checkout -b integration/<version>-brandpack rel/<version>
```

- Author `scripts/branding/presets/<name>.mjs` (copy `maruhi.mjs`): colors via
  `MARK_*` vars, output to `public/branding/<name>/` and
  `src/assets/branding/<name>/`. Wordmarks rarely work as favicon glyphs —
  keep a simple mark that reads at 16–32px.
- Generate: `pnpm run gen:favicons -- --preset <name>`.
- In `public/branding/<name>/`: `brand.yaml` (`primary_color`, `logo_url:
"/brand-logo.svg"`, product name/support email if known), `brand-logo.svg`
  (the wordmark), the fork's real `favicon.ico` if it should carry over.
- Commit the pack (vendor packs are committed — `vshare`/`linkdepot`
  precedent).
- Port deployment config (`.oci-build.json`) as its own commit.

## 5. Verify

- `pnpm run gen:favicons:check` — neutral defaults untouched.
- `git diff rel/<version>..HEAD --stat` — only the pack, preset, and
  deployment commits.
- `brand.yaml` keys ⊆ `BRAND_MANIFEST_KEYS` (`lib/onetime/config.rb`).
- Deploy with `BRAND_PACK=<name>` (runtime) or `--build-arg BRAND_PACK=<name>`
  (baked); confirm masthead logo, favicon, palette, page title, TOTP issuer.
