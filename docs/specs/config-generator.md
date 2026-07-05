# Configuration Generator

Design spec for the Configuration Generator.

Status: implemented (initial version).

## Where it lives (two pieces)

The **interactive UI lives in the docs site** (`docs.onetimesecret.com`), not in
this application. It is a self-contained, client-side tool driven by the config
JSON schemas this repo publishes — the docs site vendors the rendered schemas
and generates the YAML in the browser, with no dependency on a running instance.
See the docs repo: `src/components/config-generator/` and the page at
`/en/self-hosting/configuration-generator/`.

This repo keeps the **JSON API** counterpart: `GET /config-generator/options`
and `/config-generator/render`. These are machine-facing (no UI) — the piece
that lets a future `install.sh` pull a config for a preselected preset.

Why the split: the app runs per-region at `<region>.onetimesecret.com`, while
the docs are a separate static site. Putting the generator UI in the docs keeps
it usable without a running app and lets it track the published schemas
directly.

## What it produces

A handful of preset choices turn into ready-to-use configuration:

- an `etc/config.yaml` override fragment,
- an `etc/auth.yaml` override fragment, and
- a companion `.env` snippet listing the secret-bearing variables the operator
  still needs to supply.

It deliberately does **not** cover the full configuration surface — that lives
in `etc/defaults/*.yaml` and the Zod schemas under `src/schemas/*/config/`. The
generator is a guided starting point for the fork-in-the-road decisions a new
self-hoster makes (deployment mode, email transport, SSO, custom domains,
reverse-proxy, error tracking, default TTL), not a replacement for reading the
reference.

UX inspiration: the Caddy download/config builder and Fly.io's first-deploy
picker — configure in the browser, copy the result, continue on the command
line.

## Why override fragments, not a full re-render

`etc/defaults/{config,auth,logging}.defaults.yaml` are the single source of
truth. At boot, `Onetime::Utils::ConfigResolver` deep-merges an operator's
`etc/config.yaml` / `etc/auth.yaml` on top of those defaults
(`lib/onetime/config.rb`). So the generator only needs to emit the *keys the
operator wants to change* — exactly what a careful operator would hand-write —
and the existing merge behavior fills in everything else. Re-rendering the whole
defaults file would duplicate 1,100+ lines of authoritative YAML and guarantee
drift.

## Architecture

### This repo (JSON API)

| Layer | File |
|---|---|
| Preset catalog + fragment builder (pure, stateless) | `lib/onetime/config_generator.rb` |
| Public JSON controller | `apps/web/core/controllers/config_generator.rb` |
| Routes (all `auth=noauth`) | `apps/web/core/routes.txt` |
| Unit tests | `spec/unit/onetime/config_generator_spec.rb` |
| Endpoint tests | `apps/web/core/spec/controllers/config_generator_spec.rb` |

### Docs site (UI)

| Layer | File (docs repo) |
|---|---|
| Vendored config JSON schemas | `src/components/config-generator/schemas/*.schema.json` (+ `README.md`) |
| Preset manifest (curation + env mapping) | `src/components/config-generator/presets.ts` |
| Client-side generation logic | `src/components/config-generator/generate.ts` |
| UI island (Vue) | `src/components/config-generator/ConfigGenerator.vue` |
| Page | `src/pages/en/self-hosting/configuration-generator.astro` |

### Endpoints

- `GET /config-generator/options` — the catalog of choices (labels,
  descriptions, allowed values, defaults) as JSON.
- `GET /config-generator/render?<selection>=<value>&…` — the resulting
  `config_yaml`, `auth_yaml`, `env_snippet`, echoed `selections`, and any
  `warnings`, as JSON string fields.

The render endpoint is intentionally forgiving: unknown selection keys are
ignored and out-of-range values fall back to that option's default, so a
malformed query string never errors. Selections whose dependency is unmet (e.g.
`sso_enabled` without `deployment_mode=full`) are reset to their default and
reported in `warnings`. The docs-site generator applies the exact same rules
client-side.

## Security stance

The generator never emits a real secret value. Anything secret-bearing —
`SECRET`, `AUTH_DATABASE_URL`, `ARGON2_SECRET`, SMTP/SES/SendGrid/Lettermint
credentials, `SENTRY_DSN_BACKEND` — is only ever rendered as an **empty** `.env`
placeholder, never a generated or default value. Generator output is designed to
be safe to drop into a shareable link or a checked-in file. The endpoint has no
database access, no session, and mutates no state.

## Keeping in sync with the rest of the config surface

Per the note at the top of `lib/onetime/config.rb`, the config shape is mirrored
in several places that drift silently. This tool adds these touch points:

1. The `OPTIONS` catalog in `lib/onetime/config_generator.rb` (this repo, JSON
   API) and the parallel preset manifest in the docs repo
   (`src/components/config-generator/presets.ts`). **These two carry the same
   curated option set and must be kept in step with each other** — they are
   independent implementations (Ruby vs TypeScript) of the same presets. Adding
   or renaming a preset means editing both.
2. The `TTL_CHOICES` list (both places) — keep its bounds and default in lockstep
   with `src/schemas/shapes/config/section/secret_options.ts` (`ttl_options`).
3. The vendored schemas in the docs repo
   (`src/components/config-generator/schemas/*.schema.json`) are copies of this repo's
   `generated/schemas/config/{static,auth}.schema.json`. Re-run
   `pnpm run schemas:json:generate` and re-copy when the config Zod shapes
   change. The docs repo's `src/components/config-generator/schemas/README.md` records the exact
   provenance.

Because the catalog is a deliberately small subset, most config changes need no
update here.

The two parallel implementations (Ruby API + TypeScript docs UI) are the main
long-term cost. A future consolidation could have the docs UI drive everything
and drop the Ruby generator (if the install.sh use case is served another way),
or generate the TS preset manifest from the Ruby one. Noted, not done.

## Forward-looking (deferred — not part of this version)

- **install.sh integration.** `GET /config-generator/render` returns JSON, so an
  installer could let a user pre-select an option in the browser (on the docs
  site) and then `curl` the chosen config back on the command line (the Caddy /
  flyctl hand-off pattern). Wiring this into `install.sh` — and deciding whether
  it calls this API or a static export of the docs generator — is left for a
  follow-up.

- **Automating the schema vendor step.** The docs site currently vendors the
  rendered JSON schemas (copied in, with provenance recorded). A `schemas:sync`
  script or a drift-check in CI — or publishing the schemas to a stable URL for
  the docs build to fetch — would remove the manual re-copy. See the docs repo's
  `src/components/config-generator/schemas/README.md`.

- **Schema-driven reference tables.** The docs still mirror `etc/defaults/*.yaml`
  and `.env.reference` by hand for the reference pages. The same vendored schemas
  could drive generated reference tables there too, not just the generator.
