---
id: "024"
status: proposed
title: "ADR-024: Container Frontend Serves Built Assets — Vite Dev Mode Is a Host Concern"
---

## Status

Proposed

## Date

2026-07-11

<!--
Owner:  ops@solutious.com
Affects: dev-onboarding-problem-space (D2 bin/setup, container lane),
         docker/compose/docker-compose.simple.yml, etc/config.yaml :development,
         apps/web/core/middleware/vite_proxy.rb
-->

## Context

A containerized app started with `RACK_ENV=development` returns **500** for
`/dist/@vite/client` and `/dist/main.ts`. Cause: `development.enabled` is derived
from `RACK_ENV` (`etc/config.yaml:1120`), which flips the app into "proxy `/dist/*`
to `frontend_host`" mode (`vite_proxy.rb`), defaulting to `http://localhost:5173`
— the *container's own* loopback, where nothing listens.

The published image **cannot** satisfy that mode by construction: `Dockerfile:147`
bakes `pnpm run build` into `public/web/dist`, then `:149–151` prune prod deps,
delete `node_modules`, and uninstall pnpm. No Node dev toolchain, no Vite. So dev
mode on this image asks it to proxy to a Vite server it has no way to host.

Question raised for the onboarding work: should a container honor the
dev-vs-built-assets setting, or be fixed to one behavior?

## Decision

**The standard app container always serves built assets. It must not enter
Vite-proxy mode.** Frontend HMR is a source-editing loop and lives where the
source and Node live — on the host (`bin/dev`; the working puma + `pnpm run dev`
pair) — not as a runtime flag on the production image.

- **One contract per artifact.** The image serves what it was built with. A single
  container behavior, with no hidden external dependency, is the reproducible
  artifact the container lane exists for.
- **`RACK_ENV` is overloaded.** It is set for unrelated reasons (test lanes,
  logging, cookie flags). Coupling "where my frontend comes from" to it means one
  flag silently repurposes the image into a mode that only works if you *also*
  stand up Vite and solve container networking — failing, when you don't, as a
  bare 500 with no hint of the missing dependency. That is exactly the
  silently-broken, which-knob-is-mine DX the onboarding effort is removing.
- **Different intent, different door.** If a containerized dev loop is genuinely
  wanted, it is an explicitly-named, opt-in artifact — a `docker-compose.dev.yml`
  overlay with its own `vite` service, mounted source, and its own published ports
  (isolated from any host instance) — never a toggle on the production image.

`etc/config.yaml :development` stays as documentation of the **host** topology.

## Consequences

- `docker-compose.simple.yml` keeps `RACK_ENV=${RACK_ENV:-production}`; the simple
  lane is built-assets only. Nothing in the shipped image should react to
  `RACK_ENV=development` by proxying `/dist/*`.
- Preferred hardening: in the image, ignore the dev frontend-source switch, or
  **fail loudly** ("dev frontend mode is a host workflow; this image serves built
  assets") instead of a silent 500. Value fixed at the boundary, not by wiring a
  Vite the image can't provide.
- A future containerized HMR loop, if built, is a separate overlay + `vite`
  service; it does not change this record.
- Host frontend-dev (puma + host Vite) is unaffected and remains the primary path.

## References

- Internal — `docs/specs/install-onboarding/dev-onboarding-problem-space.md`
  (D1.2 bootable app, D2 `bin/setup`, ND1 don't require the maintainer stack);
  `etc/config.yaml` `:development` block; `apps/web/core/middleware/vite_proxy.rb`;
  `apps/web/core/views/helpers/vite_manifest.rb`; `Dockerfile:147–151`.
