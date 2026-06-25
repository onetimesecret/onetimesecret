# D3 — Production source maps emitted and served at `/dist`

- **Severity:** Medium
- **Status:** Proposed fix — **superseded by re-verification correction (2026-06-24) below**
- **Affects default config?** **Yes** — static-file serving is on by default
  (`MIDDLEWARE_STATIC_FILES != 'false'`, `config.defaults.yaml:302`), and the build emits maps unconditionally.
- **Related:** Finding 06 #3; D4 (Caddy variant re-copies the same `public/web` tree, so the maps leak
  through the proxy image too).
- **Primary files:** `vite.config.ts:283` (`sourcemap: true`),
  `lib/onetime/middleware/static_files.rb:66-75` (serves `/dist` with no extension filter),
  `fly.toml:96-98` (`[[statics]] guest_path = '/app/public/web/dist'` → `url_prefix = '/dist'`),
  `docker/variants/caddy.dockerfile:114` (`COPY ./public/web ${PUBLIC_DIR}`).

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §5).**
> Step 2 below (host-side `find public/web/dist -name '*.map' -delete` in CI) is **non-implementable as
> written** — the prescribed window does not exist. In `.github/workflows/build-and-publish-oci-images.yml`
> the **Build and push with Bake** step (`:243`, `push:` `:256`) runs **before** the **Upload frontend
> sourcemaps to Sentry** step (`:285`): the image is already built and pushed by the time Sentry runs, so
> there is no "after Sentry upload, before packaging" moment to delete maps in. The targeted
> `public/web/dist/` is also **gitignored** (`.gitignore:53`) and is produced *inside* the Docker Bake
> build stages, not on the host runner — so the host-side `find` operates on an absent/empty tree.
>
> **Correction:** strip the source maps **inside the Dockerfile build stage** — either delete `*.map`
> after the bundler emits them within the build, or (cleaner) never `COPY` them from the build stage into
> the final stage. Steps 1 (`sourcemap: 'hidden'`) and 3 (static-layer `.map` 404 guard) stand unchanged.
> Note Sentry symbolication does not depend on a host strip: the upload reads the build artifact, and with
> `'hidden'` the maps still exist in the build stage for upload before the final-stage strip.

## Problem (recap)

The Vite build sets `build.sourcemap: true` (`vite.config.ts:283`) with `outDir: '../public/web/dist'`
(`vite.config.ts:240`). That emits `*.js.map` files alongside the minified bundle **and** writes a
`//# sourceMappingURL=...` comment into each bundle. Those map files are then publicly served:

- `lib/onetime/middleware/static_files.rb:66-75` mounts `Rack::Static` for `urls: ['/dist', ...]` rooted
  at `public/web` with **no extension allowlist/denylist** — any file under `/dist`, including `*.map`,
  is served verbatim.
- `fly.toml:96-98` serves `/app/public/web/dist` at `/dist` via the Fly proxy's `[[statics]]`.
- The Caddy variant copies the whole `public/web` tree into its served root (`caddy.dockerfile:114`) and
  `file_server`s it (`etc/examples/Caddyfile-example`), so the proxy deployment leaks the maps too.

Result: the original TypeScript/Vue source structure is publicly retrievable at `/dist/assets/*.js.map`,
aiding reconnaissance of client logic and endpoints. (No server secrets are in the client bundle, hence
Medium, not High.)

The in-code comment at `vite.config.ts:219` ("Sentry sourcemaps are uploaded via CI, not at build time")
concerns *upload* of maps to Sentry for error symbolication — it does **not** stop the maps from being
emitted to disk and served.

## Root cause

`sourcemap: true` both **emits** the `.map` files and **references** them from the bundle via a
`sourceMappingURL` comment. The map files are emitted into the same directory that is shipped in the
image and served as static assets, and neither the static-file middleware, the Dockerfile, nor the
Caddy `COPY` strips them.

## Prescribed resolution

The goal: keep maps available for **Sentry symbolication** (uploaded from CI) but never publicly serve
them, and never advertise their location from the shipped bundle.

### Implementation steps

1. **Switch to `'hidden'` source maps** in `vite.config.ts:283`:
   ```ts
   // vite.config.ts (build block)
   sourcemap: 'hidden',   // emit .map for Sentry upload, but DROP the //# sourceMappingURL comment
   ```
   `'hidden'` still writes the `.map` files (so the CI `sentry-cli sourcemaps upload` step keeps working)
   but removes the `sourceMappingURL` reference from each bundle, so a browser/attacker is not pointed at
   them. This is the single most important change.

2. **Strip the `.map` files from the shipped artifact after the Sentry upload** so they are never
   reachable even by guessing the filename. In the CI build job
   (`.github/workflows/build-and-publish-oci-images.yml`), after the `sentry-cli sourcemaps upload`
   step and **before** the image is packaged:
   ```bash
   # Maps have been uploaded to Sentry; remove them from the served tree
   find public/web/dist -name '*.map' -type f -delete
   ```
   This keeps symbolication intact (Sentry already has the maps) while guaranteeing the runtime image
   contains no `.map` files for either the Ruby static server or the Caddy proxy to serve.

3. **Defence-in-depth: deny `.map` at the static layer** so a future build regression can't re-leak them.
   In `lib/onetime/middleware/static_files.rb`, after the `Rack::Static` mount, add a guard that returns
   `404` for any `*.map` request under `/dist` (e.g. a small middleware that rejects
   `env['PATH_INFO'] =~ %r{\A/dist/.*\.map\z}` before delegating). Mirror this in the Caddy config: add a
   matcher in `etc/examples/Caddyfile-example` that responds `404`/`403` to `path *.map` inside the
   `onetime-root` snippet (around the `file_server` directive, `Caddyfile-example:~184/~390`).

4. **(Optional) exclude maps from the proxy COPY** in `docker/variants/caddy.dockerfile:114`. Since maps
   are stripped in step 2 this is belt-and-suspenders, but a `.dockerignore`-style exclusion or a
   post-`COPY` `RUN find ... -name '*.map' -delete` documents intent.

### Alternatives considered

- **`sourcemap: false` (don't emit at all):** rejected — it would break Sentry symbolication of
  production frontend errors. `'hidden'` preserves the maps for upload while hiding them from clients.
- **Serve maps but gate behind auth / IP allowlist:** more moving parts, easy to misconfigure, and Sentry
  already holds the maps. Simpler to not ship them at runtime.
- **Rely only on `'hidden'` (skip the file deletion):** weaker — `'hidden'` removes the *pointer* but the
  `.map` files still sit in `/dist` and are guessable (`assets/main.<hash>.js` → `assets/main.<hash>.js.map`).
  Combine `'hidden'` with the CI strip (step 2) for a complete fix.

## Test / verification

```bash
# 1. After build, bundles no longer reference maps
pnpm run build
grep -rL "sourceMappingURL" public/web/dist/assets/*.js   # expect: all files (no reference)

# 2. After the CI strip step, no map files ship
find public/web/dist -name '*.map'                          # expect: no output

# 3. Runtime: a guessed .map URL is not served (run the app, static_files default-on)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3000/dist/assets/main.<hash>.js.map
#    -> expect 404 (not 200)

# 4. Sentry still symbolicates: trigger a frontend error and confirm the Sentry event shows
#    original TS frames (maps were uploaded by CI before deletion).
```

## Effort & risk

- **Effort:** Small — one Vite config line, one CI cleanup step, plus optional middleware/Caddy guards.
- **Risk:** Low. The only behavioral dependency is Sentry symbolication; `'hidden'` + upload-then-delete
  preserves it. Verify the CI upload runs **before** the delete (step ordering is the one thing to get
  right).
