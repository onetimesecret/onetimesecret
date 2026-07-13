# Runtime brand-asset packs (`public/branding/`)

This directory holds **brand packs**: complete sets of root-served brand assets
that overlay the neutral bundled set in `public/web/` at runtime. It is part of
the runtime brand-asset overlay introduced in
[#3739](https://github.com/onetimesecret/onetimesecret/issues/3739).

Only this README is tracked. Everything else here is **generator output and is
gitignored** — a deliberate rule that keeps the repo brand-neutral (see
#3048/#3049). The directory itself is committed via this file so it exists on a
fresh clone.

## Layout: one directory per pack

```
public/branding/
├── README.md          # tracked (this file)
├── maruhi/            # gitignored generator output
│   ├── favicon.ico
│   ├── favicon.svg
│   ├── apple-touch-icon.png
│   ├── icon-192.png
│   ├── icon-512.png
│   ├── safari-pinned-tab.svg
│   ├── social-preview.png
│   └── site.webmanifest
└── <other-pack>/      # gitignored
```

Each subdirectory is a **complete pack**. A pack may include only the files it
overrides; any asset not present in the pack falls through to the neutral
default in `public/web/`.

`default` is **not** a pack — it is the *absence* of an overlay. With no pack
selected, the neutral `public/web/` assets are served unchanged.

## Generating a pack

Packs are produced by the branding presets under
`scripts/branding/presets/*.mjs`. They are never committed; regenerate on
demand:

```bash
pnpm run gen:favicons:maruhi     # writes public/branding/maruhi/
```

The preset's `MARK_OUT_PUBLIC_DIR` (e.g. `public/branding/maruhi`) is resolved
against the repo root by `scripts/branding/generate-favicons.mjs`.

## Selecting a pack at runtime

Two knobs, one mechanism. If both are set, `BRAND_ASSETS_DIR` wins.

| Env var            | Config key              | Selects by | Example                        |
| ------------------ | ----------------------- | ---------- | ------------------------------ |
| `BRAND_PACK`       | `site.brand_pack`       | pack NAME  | `BRAND_PACK=maruhi bin/dev`    |
| `BRAND_ASSETS_DIR` | `site.brand_assets_dir` | PATH       | `BRAND_ASSETS_DIR=/mnt/brand`  |

- `BRAND_PACK` is a bare **name** resolved to `public/branding/<name>`. Path
  separators are rejected — it is a name, not a path.
- `BRAND_ASSETS_DIR` is an explicit **path**, intended for runtime mounts
  (e.g. a Docker/Kubernetes volume at `/mnt/brand`).

The overlay stack is built once at boot, so adding or changing files in a
selected pack requires a restart to take effect.

## Baking a pack into a Docker image

The pack can also be baked at build time (optional; the runtime knobs above are
the primary path):

```bash
# after generating public/branding/maruhi/
docker build --build-arg BRAND_PACK=maruhi .
```

The Dockerfile copies the selected pack into `public/web/` during the build. It
fails the build if `BRAND_PACK` names a pack that was never generated, so a typo
can't silently ship neutral assets.
