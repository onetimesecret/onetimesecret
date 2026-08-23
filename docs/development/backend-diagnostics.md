# Backend Diagnostics (Sentry)

Error tracking and tracing via `sentry-ruby` (6.5), reporting to self-hosted
Sentry at catch.onetimesecret.com. Everything lives in
`lib/onetime/initializers/setup_diagnostics.rb`; request capture is
`Sentry::Rack::CaptureExceptions` in `lib/onetime/application/middleware_stack.rb`.

## Configuration

- `diagnostics.enabled` — master switch. Off → `Runtime.infrastructure.d9s_enabled = false`, no gem loaded.
- `diagnostics.sentry.backend.dsn` — web/cli processes.
- `diagnostics.sentry.workers.dsn` — worker/scheduler processes; falls back to backend DSN.
- `diagnostics.sentry.backend.org_id` — enables `strict_trace_continuation` (rejects foreign-org trace baggage). Must be set explicitly for self-hosted Sentry.
- Release: `SENTRY_RELEASE` env var, else `.commit_hash.txt` (baked by CI), else git/dev fallback. Matches frontend so both report the same release.
- Actor references — derived from the customer's external identifier (extid), HMAC'd under `ACCOUNT_ID_SECRET` and truncated to 16 hex chars. That secret is the only keying; there is no scope axis and no residency knob, because the pre-image is minted per installation. With no `ACCOUNT_ID_SECRET`, no actor reference is emitted. References re-key when `ACCOUNT_ID_SECRET` rotates — and once more on the deploy that shipped the extid pre-image — so expect a correlation discontinuity of up to the Sentry retention window after either. See [the environment reference](../../.env.reference) for rotation requirements and [the decision record](../specs/diagnostics/actor-ref-preimage-debate-decision.md) for why the email pre-image was dropped.

Sampling: errors 100%, traces 10%, profiles 10% of sampled traces.
`send_default_pii` stays at the default (false) — no IP addresses collected.

## Tags

Set once at boot via `Sentry.set_tags`:

- `site_host` — deployment identity
- `service` — `web` or `worker` (from execution mode)
- `jurisdiction` — lowercased region code, omitted if unconfigured

Selected request and controller error captures set Sentry `user.id` to the
same opaque `actor_ref` the frontend receives. This supports issue correlation
and affected-account counts within this installation; it is not product
analytics, behavioral profiling, or a cross-installation identity join. The ref
is not a direct identifier, but it is potentially personal data. Other capture
paths can remain unattributed, so a missing `user.id` does not establish that
an event came from an anonymous session or an unconfigured deployment — capture
sites that hold no extid (account creation, email-only credential flows,
datastore-outage rescues) are unattributed by design.

Organization correlation is not active: although the backend may emit an
`organization_ref` on the Colonel organization-detail response, the current
frontend response contract discards it and does not attach an organization tag
to Sentry.

## Scrubbing

Sensitive values (secret identifiers, auth tokens, emails) are removed
before events leave the process. Two hooks, because sentry-ruby routes error
events and transaction events separately:

- `before_send` → `scrub_event_urls` + `scrub_event_messages`. Covers
  `request.url`, `event.transaction` (raw `PATH_INFO` from the Rack
  middleware), `contexts['request']['url']`, exception message strings, and
  `capture_message` strings.
- `before_send_transaction` → `scrub_transaction_event`. Same URL rules plus
  spans: `:description` (free text), `data['url']`, `data['http.query']`. It
  intentionally does not call `scrub_event_messages`: transaction events carry
  spans and URLs, not the exception `values`/`message` fields that
  `scrub_event_messages` scrubs, so there is nothing for it to do.

Rules (all in `SetupDiagnostics` class methods):

- Identifier paths (`/secret/`, `/receipt/`, `/private/`, `/metadata/`, `/incoming/`): segment redacted when ≥ 20 base36 chars (62 = v0.24, 31 = legacy v0.23; named actions like `/receipt/recent` pass through).
- Auth token paths (`/forgot/`, `/l/`, `/auth/reset-password/`, `/account/email/confirm/`) and `/colonel/*`: always redacted.
- Query params `key`, `secret`, `token`, `passphrase`: values redacted.
- Free text: emails → `[EMAIL_REDACTED]`; 62/31-char base36 identifiers → `[REDACTED]`. The two branches are anchored differently: the 62-char branch is **unanchored** so identifiers glued to adjacent word characters (`?ref=<id>abc`, `<id>x`, `load <id>_meta`) are still caught — this deliberately over-redacts any ≥62-char base36 run, which is fail-safe since no ops-useful token reaches that length. The 31-char legacy branch stays `\b` word-bounded and length-exact so 32-hex trace IDs and 40-hex commit hashes survive.

Failure semantics: fail closed. URL scrub errors redact to
`[SCRUBBING_FAILED]`; transaction scrub errors drop the event.

## Verifying

- `spec/unit/onetime/initializers/setup_diagnostics_spec.rb`
- Sentry doctor CLI: `lib/onetime/cli/diagnostics/sentry/doctor_command.rb`

Frontend counterpart: [frontend-diagnostics.md](frontend-diagnostics.md).
The scrub rules intentionally mirror `src/plugins/core/diagnostics/scrubbers.ts`.
