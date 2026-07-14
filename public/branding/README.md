# Brand packs (`public/branding/`)

This directory holds **brand packs**: complete sets of root-served brand assets
(`favicon.ico`, `favicon.svg`, `apple-touch-icon.png`, `icon-192/512.png`,
`safari-pinned-tab.svg`, `social-preview.png`, `site.webmanifest`) plus an
optional `brand.yaml` identity manifest. A pack is the single unit of branding:
assets and the identity values that go with them, together. Introduced by the
runtime brand-asset overlay ([#3739](https://github.com/onetimesecret/onetimesecret/issues/3739))
and consolidated into packs in v2 ([#3774](https://github.com/onetimesecret/onetimesecret/issues/3774)).

## `default` is a tracked pack — everything else is gitignored

```
public/branding/
├── README.md          # tracked (this file)
├── default/           # tracked (#3774): the neutral keyhole pack
│   ├── favicon.ico … site.webmanifest   # neutral asset set
│   └── brand.yaml                        # value-free manifest (all keys commented)
├── maruhi/            # gitignored generator output
│   └── …
└── <other-pack>/      # gitignored
```

Only this README **and the `default/` pack** are tracked. Every other pack is
**generator output and gitignored** — a deliberate rule that keeps the repo
brand-neutral (see #3048/#3049). The company's own marks (`maruhi`,
`onetimesecret`) are presets you regenerate on demand, never committed assets.

**`default` IS the neutral pack** (v2, #3774). Brand-pack resolution ALWAYS lands
on a pack: an unset `BRAND_PACK` resolves to `default`, which holds the neutral
asset set and a value-free `brand.yaml`. (Before #3774, "default" meant the
*absence* of an overlay and the neutral files lived loose in `public/web/`.)

## Two search roots for a pack NAME

A `BRAND_PACK` name is resolved across two roots, first existing wins:

1. `etc/branding/<name>/` — **operator space**. Nothing tracked here in the repo;
   it arrives at runtime (quadlet mounts, systemd confext, a Docker/K8s volume).
   Checked first, so an operator pack shadows a vendor pack of the same name.
2. `public/branding/<name>/` — **vendor space** (this directory): the tracked
   `default` plus any generated packs baked into the image.

The `default` pack lives in the vendor root on purpose: a quadlet mount of a host
`branding/` dir lands wholesale over `etc/branding`, so a tracked
`etc/branding/default` would be shadowed exactly when packs are in use.

## The `brand.yaml` manifest

A pack may carry a `brand.yaml` with identity scalars (colours, product name).
They are absorbed into `OT.conf['brand']` at boot, with precedence:

```
built-in defaults  <  pack brand.yaml  <  operator `brand:` config  <  BRAND_* env
```

Keys are whitelisted to the `BRAND_*` identity set (`Config::BRAND_MANIFEST_KEYS`)
and read with `YAML.safe_load` — a pack can never set `site.host`, SMTP creds, or
any non-brand config. The `default` pack's `brand.yaml` is **value-free** (every
key commented out), so an unconfigured install adds no brand values; it doubles
as the authoring template. See `default/brand.yaml`.

## Generating a pack

Packs are produced by the branding presets under `scripts/branding/presets/*.mjs`
(company packs are never committed — regenerate on demand):

```bash
pnpm run gen:favicons             # regenerate the neutral default/ pack (tracked)
pnpm run gen:favicons:maruhi      # example preset → public/branding/maruhi/
```

A preset run also emits an active `brand.yaml` (colour + product name) into its
pack; the neutral `default` keeps its value-free template. See
[`scripts/branding/README.md`](../../scripts/branding/README.md).

## Selecting a pack at runtime

Two knobs, one mechanism. If both are set, `BRAND_ASSETS_DIR` wins.

| Env var            | Config key              | Selects by | Example                        |
| ------------------ | ----------------------- | ---------- | ------------------------------ |
| `BRAND_PACK`       | `site.brand_pack`       | pack NAME  | `BRAND_PACK=maruhi bin/dev`    |
| `BRAND_ASSETS_DIR` | `site.brand_assets_dir` | PATH       | `BRAND_ASSETS_DIR=/mnt/brand`  |

- `BRAND_PACK` is a bare **name** resolved across the two roots above. Path
  separators are rejected — it is a name, not a path. Unset ⇒ `default`; an
  unknown name falls back to `default` (and warns).
- `BRAND_ASSETS_DIR` is an explicit **path**, intended for runtime mounts (e.g. a
  Docker/Kubernetes volume at `/mnt/brand`). A missing path falls back to
  `default`.

A selected pack may be partial: any asset it omits falls through to the `default`
pack. The overlay stack is built once at boot, so adding or changing files in a
selected pack requires a restart.

## Baking a pack into a Docker image

Optional (the runtime knobs above are the primary path). After generating a pack:

```bash
docker build --build-arg BRAND_PACK=maruhi .
```

The Dockerfile overlays the selected pack onto `public/branding/default/` during
the build, so the runtime serves it with no env var set. It fails the build if
`BRAND_PACK` names a pack that was never generated, so a typo can't silently ship
neutral assets.
