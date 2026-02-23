# Docker Bake Architecture

## The Problem

One monolithic Dockerfile mixed build infrastructure (Ruby, Node, system packages) with app-specific layers. Three CI
jobs duplicated tag logic. Keeping Docker config in sync across versions was expensive.

The Solution: Separation via Bake

docker/
  base.dockerfile    ← SHARED: Ruby + Node + build tools + yq + appuser
  bake.hcl           ← Orchestration: targets, tags, registry logic
Dockerfile           ← APP-SPECIFIC: deps → build → final stages (thin)

## Build Graph

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

Key: base and main are injected as build contexts via contexts = { base = "target:base" } in bake.hcl. Bake resolves the
  DAG automatically — no separate registry push needed.

Why final stages still use ruby:3.4-slim directly

base includes build-essential, git, python3, etc. — needed for bundle install / pnpm install but unwanted in production.
  The final and final-s6 stages start fresh from the slim image and COPY only runtime artifacts, keeping images small.

### Bake Targets & Groups

```
┌────────┬──────────────────────────────────┬──────────┬─────────────────────────────────┐
│ Target │            Dockerfile            │  Stage   │           Description           │
├────────┼──────────────────────────────────┼──────────┼─────────────────────────────────┤
│ base   │ docker/base.dockerfile           │ —        │ Build toolchain (not pushed)    │
├────────┼──────────────────────────────────┼──────────┼─────────────────────────────────┤
│ main   │ Dockerfile                       │ final    │ Single-process production image │
├────────┼──────────────────────────────────┼──────────┼─────────────────────────────────┤
│ s6     │ Dockerfile                       │ final-s6 │ Multi-process (S6 overlay)      │
├────────┼──────────────────────────────────┼──────────┼─────────────────────────────────┤
│ lite   │ docker/variants/lite.dockerfile  │ —        │ All-in-one with embedded Redis  │
├────────┼──────────────────────────────────┼──────────┼─────────────────────────────────┤
│ caddy  │ docker/variants/caddy.dockerfile │ —        │ TLS reverse proxy               │
└────────┴──────────────────────────────────┴──────────┴─────────────────────────────────┘

┌─────────┬───────────────────────┬───────────────────────────────────────┐
│  Group  │        Targets        │                  Use                  │
├─────────┼───────────────────────┼───────────────────────────────────────┤
│ default │ main                  │ docker buildx bake -f docker/bake.hcl │
├─────────┼───────────────────────┼───────────────────────────────────────┤
│ ci      │ main, s6, lite        │ What GitHub Actions builds            │
├─────────┼───────────────────────┼───────────────────────────────────────┤
│ all     │ main, s6, lite, caddy │ Everything                            │
└─────────┴───────────────────────┴───────────────────────────────────────┘
```

### Tag Strategy

Tags are computed in CI as EXTRA_TAGS (comma-separated), passed as an env var. The tags() HCL function distributes them
across registries:

```
┌─────────────────────┬────────────────────┐
│        Event        │     EXTRA_TAGS     │
├─────────────────────┼────────────────────┤
│ v1.0.0 tag push     │ latest             │
├─────────────────────┼────────────────────┤
│ v1.0.0-rc1 tag push │ next               │
├─────────────────────┼────────────────────┤
│ Branch push         │ {branch-name},edge │
├─────────────────────┼────────────────────┤
│ develop push        │ next               │
├─────────────────────┼────────────────────┤
│ Manual dispatch     │ dev or custom      │
├─────────────────────┼────────────────────┤
│ Nightly schedule    │ nightly            │
└─────────────────────┴────────────────────┘

REGISTRY_MODE=custom routes all tags to a single private registry instead of GHCR+DockerHub.
```

### Commands

```
docker buildx bake -f docker/bake.hcl --print   # inspect resolved config
docker buildx bake -f docker/bake.hcl main       # build main
docker buildx bake -f docker/bake.hcl ci         # build what CI builds
pnpm docker:bake:print                           # npm alias for --print
pnpm docker:build                                # npm alias for main
```

### Constraint

Plain docker build . no longer works — FROM base requires Bake to inject the context. This is intentional; all builds go
  through docker buildx bake.
