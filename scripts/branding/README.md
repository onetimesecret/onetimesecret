# `scripts/branding/` — favicon & brand-asset generator

Generates the root-served brand-asset pack (`favicon.ico`, `favicon.svg`,
`apple-touch-icon.png`, `icon-192/512.png`, `safari-pinned-tab.svg`,
`site.webmanifest`, `social-preview.png`) from a single glyph + palette. The
committed neutral pack in `public/web/` is produced here; so are the optional,
_uncommitted_ brand packs that overlay it at runtime (#3739).

- `mark.mjs` — single source of truth for glyph geometry and the neutral
  palette. Reads generator-only `MARK_*` env vars (deliberately **not** the
  runtime `BRAND_*` vars, so an ambient `BRAND_PRIMARY_COLOR` can't re-skin the
  neutral defaults).
- `generate-favicons.mjs` — the rasterizer (`pnpm run gen:favicons`).
- `presets/*.mjs` — named `MARK_*` override bundles (see below).
- `check.mjs` / `mark.test.mjs` — CI guards over the committed neutral pack and
  the generator's pure logic.

For the runtime side (selecting/serving a pack, chokepoints, helpers) see
[`docs/architecture/branding.md`](../../docs/architecture/branding.md) and
[`docs/product/branding-favicon.md`](../../docs/product/branding-favicon.md).

## Preset-per-pack convention

A **preset** is a named data file at `presets/<name>.mjs` that default-exports a
`{ MARK_*: value }` object — a set of overrides applied as env defaults, not a
fork of the generator. One code path produces every pack. `maruhi` and `current`
are example presets (each an operator's own branding); the OSS repo itself ships
only the neutral default and treats these as sample overlays, not the product
identity.

Each preset points its output at a **pack directory** under
`public/branding/<name>/` via `MARK_OUT_PUBLIC_DIR`, plus a reviewable source-SVG
copy under `src/assets/branding/<name>/`. It never writes to `public/web/`, so
the committed neutral pack (and its CI guard) is untouched.

## Packs live in `public/branding/<pack>/` — never committed

Pack image files are **generator output and gitignored** (only
`public/branding/README.md` is tracked) — a deliberate rule that keeps generated
brand assets out of version control (#3048/#3049). This keeps the repo
brand-neutral: the branding lives here as preset _code_, not as committed
assets. Regenerate a pack on demand rather than checking it in.

`default` is **not** a pack — it is the _absence_ of an overlay. With no pack
selected, the neutral `public/web/` assets are served unchanged.

## Generating a pack

```bash
pnpm run gen:favicons             # neutral pack → public/web/ (committed)
pnpm run gen:favicons:maruhi      # example preset → public/branding/maruhi/
```

`gen:favicons:<preset>` runs `generate-favicons.mjs --preset <name>`. The
preset's `MARK_OUT_PUBLIC_DIR` (e.g. `public/branding/maruhi`) is resolved
against the repo root. Override any value inline, e.g.
`MARK_PRIMARY_COLOR='#…' pnpm run gen:favicons:maruhi`.

To add your own pack, copy `presets/maruhi.mjs` to `presets/<name>.mjs`, set
`MARK_OUT_PUBLIC_DIR: 'public/branding/<name>'`, then run
`pnpm run gen:favicons --preset <name>`. Unknown `MARK_*` keys in a preset are
reported and skipped, not silently ignored.

## Selecting a pack at runtime

Two knobs, one mechanism (#3739). If both are set, `BRAND_ASSETS_DIR` wins.

| Env var            | Config key              | Selects by | Example                       |
| ------------------ | ----------------------- | ---------- | ----------------------------- |
| `BRAND_PACK`       | `site.brand_pack`       | pack NAME  | `BRAND_PACK=maruhi bin/dev`   |
| `BRAND_ASSETS_DIR` | `site.brand_assets_dir` | PATH       | `BRAND_ASSETS_DIR=/mnt/brand` |

- `BRAND_PACK` is a bare **name** resolved to `public/branding/<name>/`. Path
  separators are rejected — it is a name, not a path.
- `BRAND_ASSETS_DIR` is an explicit **path**, intended for runtime mounts (e.g. a
  Docker/Kubernetes volume at `/mnt/brand`).

Files present in the selected directory are served; anything absent falls
through to the neutral `public/web/` default. The overlay stack is built once at
boot, so adding or changing files in a selected pack requires a restart.

## Baking a pack into a Docker image

Optional — the runtime knobs above are the primary path. After generating a
pack, select it at build time:

```bash
docker build --build-arg BRAND_PACK=maruhi .
```

The Dockerfile copies `public/branding/<pack>/` into `public/web/` during the
build. It **fails the build** if `BRAND_PACK` names a pack that was never
generated, so a typo or an ungenerated pack can't silently ship the neutral
assets.
