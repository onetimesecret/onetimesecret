# Frontend Diagnostics (Sentry)

Error tracking via `@sentry/browser` / `@sentry/vue` (v10), reporting to
self-hosted Sentry at catch.onetimesecret.com. Plugin:
`src/plugins/core/enableDiagnostics.ts`. Module-level capture API
(`captureException` / `captureMessage` for non-Vue contexts):
`src/services/diagnostics.service.ts`.

## Architecture

Isolated-client pattern: explicit `BrowserClient` + `Scope`, no global
`Sentry.init`. Consequence: anything the SDK would normally put on the global
scope must be set on our scope directly — transaction names come from a
`router.afterEach` hook that sets the matched route record's parameterized
path (`/secret/:secretKey`), never the resolved URL.

Config arrives from the backend via bootstrap (`config.sentry`: DSN,
environment, sample rates). Release is `__SENTRY_RELEASE__` at build time so
events match the sourcemaps uploaded for that bundle, even when a CDN serves
an older frontend than the running backend.

Sampling: errors 100% (`sampleRate` overridable), traces 1% default.
`sendDefaultPii` stays false. Session Replay is disabled (CSP conflict with
blob workers — see comment in the integrations list).

## Integrations

Tree-shaken explicit list: `breadcrumbs`, `globalHandlers`, `linkedErrors`,
`dedupe`, `httpContext` (attaches `request.url` — without it events have no
URL), `eventFilters` (noise reduction), `browserApiErrors` (full async stack
traces), `functionToString`, `browserTracing({ router })`.

## Tags

On the base scope: `service: web`, `site_host` (display domain),
`jurisdiction` (from bootstrap regions). Per-event indexed tags via the
`context` argument of `captureException` — see `TAG_FIELDS` in
diagnostics.service.ts (`errorType`, `schema`, `planid`, `role`, ...).

## Scrubbing

Three hooks; all defined in enableDiagnostics.ts, patterns in
`src/plugins/core/diagnostics/scrubbers.ts`:

- `beforeSend` — exception/message strings, `request.url`, `transaction`, breadcrumb URLs. Two layers: route-param value scrubbing (opt out per route with `meta.sentryScrubParams: false` — governs param values only) plus an always-on pattern net (emails, 62-char identifiers, sensitive paths).
- `beforeSendTransaction` — performance events bypass `beforeSend`; scrubs transaction name, `request.url`, span descriptions (free-text scrubber — the URL scrubber would mangle `GET /path` strings), and span `url` / `http.url` / `url.full` data.
- `beforeBreadcrumb` — navigation breadcrumbs via `router.resolve()` metadata; xhr/fetch breadcrumbs via patterns.

Path patterns are generated from Otto routes marked `sensitive=true`:
`src/generated/sentry-scrub-patterns.ts`, regenerate with
`pnpm run generate:sentry-patterns`. `scrubbers.ts` keeps a legacy fallback
pattern for anything the generated set misses.

## Verifying

`pnpm vitest run src/tests/plugins/core/diagnostics/` plus
`src/tests/services/diagnostics.service.spec.ts`.

Backend counterpart: [backend-diagnostics.md](backend-diagnostics.md).
Scrub rules intentionally mirror `lib/onetime/initializers/setup_diagnostics.rb`.
