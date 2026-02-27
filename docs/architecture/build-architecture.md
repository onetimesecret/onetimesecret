# OCI Build Architecture

The build workflow produces multiple OCI image variants from a single codebase, targeting both Docker and Podman runtimes across GitHub Actions CI and a self-hosted Gitolite build server. The core design separates reusable build infrastructure (Ruby, Node, system packages) into a shared base image that is built once and injected into downstream Dockerfiles via named build contexts, eliminating duplication across the main, S6 multi-process, and lite all-in-one variants. Docker Bake orchestrates the dependency graph in CI, while the Gitolite post-receive hook achieves the same result using native Podman `--build-context` flags with no additional tooling. Both paths read from the same Dockerfiles and produce identical images. The architecture is designed to share the base across v0.24 and v0.23 codebases, so that Ruby and Node version pins, system package lists, and security patches propagate to both versions from a single file change.

## File Layout

```
docker/
  base.dockerfile          Shared: Ruby 3.4 + Node 22 + build tools + yq + appuser (UID 1001)
  bake.hcl                 Orchestration: targets, tag function, registry routing
  entrypoints/             App-specific startup logic
  s6/services/             S6 process supervision definitions
  variants/
    lite.dockerfile        All-in-one (app + Redis, ephemeral)
    caddy.dockerfile       TLS proxy

Dockerfile                 App stages only: dependencies → build → final-s6 / final
.oci-build.json            Gitolite build server config (base + variant declarations)
build-and-deploy.py        Post-receive hook (reads .oci-build.json, drives podman build)
```

## Build Graph

```
base.dockerfile          Dockerfile                    lite.dockerfile
┌─────────┐         ┌──────────────┐              ┌─────────────┐
│  base   │────────▶│ dependencies │              │    lite      │
│ (tools) │ context │ (bundle,pnpm)│              │ (app+redis)  │
└─────────┘         └──────┬───────┘              └──────▲───────┘
                           │                             │
                    ┌──────▼───────┐              context│
                    │    build     │                     │
                    │ (vite, meta) │              ┌──────┴───────┐
                    └──┬───────┬───┘              │    main      │
                       │       │                  │  (final)     │
                ┌──────▼──┐ ┌──▼──────┐           └──────────────┘
                │final-s6 │ │  final  │─────────────────┘
                │ (+S6)   │ │(default)│
                └─────────┘ └─────────┘
```

`base` and `main` are injected as named build contexts. In CI, Bake resolves this via `contexts = { base = "target:base" }`. On the Gitolite build server, the post-receive hook passes `--build-context base=container-image://ots-base:{sha}` to Podman.

`final` and `final-s6` start fresh from `ruby:3.4-slim` (not from base). Base carries build-essential, git, python3 (~400MB) needed for `bundle install` and `pnpm install` but unwanted in production images (~200MB).

## Two Build Paths, Same Images

### Path 1: GitHub Actions (Docker Bake)

```
.github/workflows/build-and-publish-oci-images.yml
  → docker/bake-action@v6
    → reads docker/bake.hcl
      → resolves target DAG (base → main/s6, main → lite)
      → pushes to GHCR + DockerHub (or custom registry)
```

Single job replaced three parallel jobs. The old composite action (`.github/actions/build-and-publish-oci-image/`) was deleted — fully absorbed by bake.hcl.

Tag logic is computed in a shell step as `EXTRA_TAGS` (comma-separated), passed as an env var. The `tags()` HCL function distributes them across registries. User-controlled inputs use `env:` variables in `run:` blocks, never inline `${{ }}` (injection-safe).

### Path 2: Gitolite Build Server (Podman)

```
git push build main
  → post-receive hook
    → build-and-deploy.py
      → reads .oci-build.json from pushed revision (git show, no checkout yet)
      → reads gitolite-options.oci.registry and oci.image-name from git config
      → overrides .oci-build.json registry/image_name when gitolite options present
      → git archive → tar export to /opt/builds/
      → if "base" key present:
          podman build -f docker/base.dockerfile → ots-base:{sha} (local only)
      → for each variant (in array order):
          podman build --build-context base=container-image://ots-base:{sha} ...
          podman push (all tags)
      → podman rmi ots-base:{sha}  (cleanup)
```

**Backward compatibility**: if `.oci-build.json` has no `"base"` key, the script runs the old code path unchanged. The `build_contexts` parameter defaults to `None` and no `--build-context` flags are added.

**Inter-variant contexts**: lite declares `"contexts": {"main": ""}` — the `""` references the variant with suffix `""` (main). The script tracks `built_images[suffix] = first_tag` as each variant completes. Variant array order is the dependency order.

## Bake Targets & Groups

```
Target   Dockerfile                        Stage      Description
──────   ──────────────────────────────     ────────   ──────────────────────────────
base     docker/base.dockerfile            —          Build toolchain (not pushed)
main     Dockerfile                        final      Single-process production image
s6       Dockerfile                        final-s6   Multi-process (S6 overlay)
lite     docker/variants/lite.dockerfile   —          All-in-one with embedded Redis
caddy    docker/variants/caddy.dockerfile  —          TLS reverse proxy

Group     Targets                When
───────   ─────────────────────  ─────────────────────────────────────
default   main                   pnpm docker:build
ci        main, s6, lite         GitHub Actions
all       main, s6, lite, caddy  Full local build
```

## Tag Strategy

Two variables control Docker image tags:

- **`IMAGE_TAG`** — v-prefixed version for release builds (e.g. `v0.24.0-rc15`). Empty for non-release builds, which suppresses the version tag entirely.
- **`EXTRA_TAGS`** — comma-separated additional tags (e.g. `latest`, `next`, `nightly`). Always applied when non-empty.

`VERSION` (clean semver) is used only for build args and OCI labels — never as a Docker tag.

```
Event                 IMAGE_TAG         EXTRA_TAGS            Registries
────────────────────  ────────────────  ────────────────────  ──────────────────────────────
v1.0.0 tag push       v1.0.0            latest                GHCR + DockerHub (or custom)
v1.0.0-rc1 tag push   v1.0.0-rc1        next                  "
Branch push           (empty)           {branch-name},edge    "
develop push          (empty)           next                  "
Manual dispatch       (empty)           dev or custom         "
Nightly schedule      (empty)           nightly               "
```

`REGISTRY_MODE=custom` routes all tags to a single private registry instead of GHCR+DockerHub.

## Podman Tooling

On Linux build machines, [bakah](https://github.com/emersion/bakah) can also execute our bake.hcl via Buildah's Go library:

```bash
docker buildx bake -f docker/bake.hcl ci --print | bakah -f -
```

`docker buildx bake --print` is used purely as an HCL-to-JSON parser. Bakah resolves `target:base` dependencies, builds in parallel with `--jobs`, and executes entirely through Buildah. Bakah requires Linux (Buildah library calls into the kernel directly).

The Gitolite post-receive hook does not use bakah — it uses native `podman build --build-context` which works without additional dependencies.

## .oci-build.json Schema

```jsonc
{
  "registry": "ghcr.io",
  "image_name": "onetimesecret/onetimesecret",
  "platforms": ["linux/amd64"],

  // Optional. When present, enables bake-aware mode.
  // Omit entirely for legacy (plain podman build per variant).
  "base": { "dockerfile": "docker/base.dockerfile" },

  "variants": [
    // Order matters: dependencies must precede dependents.
    { "suffix": "", "dockerfile": "Dockerfile", "target": "final" },
    { "suffix": "-s6", "dockerfile": "Dockerfile", "target": "final-s6" },
    {
      "suffix": "-lite",
      "dockerfile": "docker/variants/lite.dockerfile",
      // "contexts" maps context names to variant suffixes.
      // "" = the variant with suffix "" (main).
      "contexts": { "main": "" }
    }
  ]
}
```

## Registry Configuration

Registry and image name follow a layered precedence: **Gitolite options > .oci-build.json > repo name fallback**. This keeps private infrastructure details out of the application repository while preserving self-documenting defaults in `.oci-build.json`.

### Gitolite per-repo options (build server)

The post-receive hook reads `gitolite-options.*` from the bare repo's git config. Gitolite populates these from `option` lines in `gitolite.conf`:

```
# In gitolite-admin/conf/gitolite.conf
repo onetimesecret
    option oci.registry = registry.example.com
    option oci.image-name = myorg/onetimesecret
```

When present, these override the corresponding `.oci-build.json` fields. When absent, `.oci-build.json` values are used as-is.

### build-and-deploy.py changes

The hook needs a helper to read gitolite options from the bare repo's git config:

```python
def _gitolite_option(repo: Repo, key: str) -> str | None:
    """Read a gitolite per-repo option from git config.

    Gitolite stores 'option X = Y' as 'gitolite-options.X = Y'
    in the repo's git config.
    """
    try:
        return repo.git.config(f"gitolite-options.{key}").strip()
    except Exception:
        return None
```

In `BuildConfig.load()`, the gitolite options override `.oci-build.json` after parsing:

```python
# Gitolite options override .oci-build.json values
registry = _gitolite_option(repo, "oci.registry") or raw["registry"]
image_name = (
    _gitolite_option(repo, "oci.image-name")
    or raw.get("image_name", repo_name)
)
```

The rest of `BuildConfig.load()` is unchanged — `platforms`, `variants`, `base`, and `work_dir` still come from `.oci-build.json` only.

### Precedence table

```
Field         Gitolite option       .oci-build.json    Fallback
────────────  ────────────────────  ─────────────────  ──────────────
registry      oci.registry          "registry"         (required)
image_name    oci.image-name        "image_name"       repo directory name
```

### CI path (GitHub Actions)

CI does not use `.oci-build.json` or gitolite options. Registry routing is controlled by `REGISTRY_MODE` and `CUSTOM_REGISTRY` environment variables in the workflow, applied via the `tags()` function in `bake.hcl`.

## Commands

```bash
# Docker (CI + local dev)
docker buildx bake -f docker/bake.hcl --print    # inspect resolved config
docker buildx bake -f docker/bake.hcl main        # build main
docker buildx bake -f docker/bake.hcl ci          # build what CI builds
pnpm docker:bake:print                            # alias for --print
pnpm docker:build                                 # alias for main

# Podman (Linux build machines)
pnpm podman:build                                 # bakah path (main)
pnpm podman:bake                                  # bakah path (ci group)

# Override variables
EXTRA_TAGS="latest,edge" VERSION="0.24.1" \
  docker buildx bake -f docker/bake.hcl ci

# Custom registry
REGISTRY_MODE="custom" CUSTOM_REGISTRY="registry.example.com" \
  docker buildx bake -f docker/bake.hcl main
```

## Verification

```bash
# Docker Bake (CI path)
docker buildx bake -f docker/bake.hcl --print          # all targets resolve without error
docker buildx bake -f docker/bake.hcl main              # main image builds successfully
docker run --rm <image>:<tag> ruby --version             # Ruby present in final image

# Podman (Gitolite path) — run on the build server
podman build -f docker/base.dockerfile --tag ots-base:test .
podman build -f Dockerfile --target final \
  --build-context base=container-image://ots-base:test \
  --tag ots-main:test .
podman build -f docker/variants/lite.dockerfile \
  --build-context main=container-image://ots-main:test \
  --tag ots-lite:test .
podman rmi ots-base:test ots-main:test ots-lite:test     # cleanup

# Post-receive hook (end-to-end)
git push build main                                      # triggers hook, check remote: output
```

## Decisions

**No standalone `docker build` fallback.** `FROM base` in the Dockerfile resolves only when Bake (or Podman with `--build-context`) injects it. Could keep inline base stages that Bake overrides, but then base is maintained in two places. Chose single source of truth over convenience.

**Final images don't inherit from base.** `final` and `final-s6` start from `ruby:3.4-slim` and COPY artifacts from the build stages. This keeps production images at ~200MB instead of ~600MB.

**Lite uses `FROM main` context, not a registry digest.** The old lite.dockerfile pinned `ghcr.io/onetimesecret/...@sha256:...` — a digest that went stale on every main image update. Now Bake/Podman builds main first and injects it. Always in sync, zero manual maintenance.

**Podman path uses native `--build-context`, not bakah.** The Gitolite hook runs on a Linux server where `podman build --build-context name=container-image://image` works natively. No extra binary to install or maintain. Bakah is available as an alternative for teams that want full bake.hcl execution via Podman.

**Pinned image digests live in one place.** Ruby and Node SHA256 digests are in `docker/base.dockerfile` only. Both v0.24 and v0.23 (when backported) share this file. Version bumps happen once.

**Tag computation avoids injection.** CI workflow uses `env:` variables for user-controlled inputs (`inputs.version_tag`), never interpolating `${{ inputs.* }}` directly in `run:` blocks.

**Variant array order is the build order.** The post-receive hook builds variants sequentially in the order declared in `.oci-build.json`. A variant's `"contexts"` can only reference suffixes that appear earlier in the array. This is enforced at runtime with a clear error message.

**Registry URL lives in gitolite config, not the repo.** `.oci-build.json` carries public defaults (GHCR). The post-receive hook reads `gitolite-options.oci.registry` and `gitolite-options.oci.image-name` from the bare repo's git config, overriding `.oci-build.json` when present. Private registry URLs never appear in application commits. CI uses its own env vars (`REGISTRY_MODE`, `CUSTOM_REGISTRY`) via `bake.hcl`.

## What's Next

Phase 5 (v0.23 backport) is complete on `feature/docker-backport`. The v0.23 branch shares `base.dockerfile` with v0.24 and uses a v0.23-specific Dockerfile (Thin server, v0.22→v0.23 config migration, appuser). Bake targets: main + lite (no S6). Merges cleanly into `rel/0.23`.
