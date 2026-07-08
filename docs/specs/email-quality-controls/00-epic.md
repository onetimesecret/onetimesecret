---
labels: email-quality, work, architecture
depends: none
epic: TBD
---

# Email Quality Controls — suppression, feedback ingestion, outbound limits, one-click unsubscribe (tracking)

## Summary

Give the multi-tenant transactional mailer the reputation controls it has never
had: a send-time suppression list keyed by hashed recipient address, automatic
bounce/complaint ingestion from the delivery providers, per-address and
per-domain outbound rate limits, RFC 8058 one-click unsubscribe on every
recipient-facing and notification email, and a recipient-confirmed opt-back-in
flow. Everything is built in the Operations style proven by the Colonel Admin
Rebuild (epic #3653): each verb is written once as an `Onetime::Operations::*`
class, and the colonel API, admin UI, and `bin/ots` CLI are thin adapters over
it. Enforcement lives at the one place 100% of outbound mail already converges
(`Onetime::Mail::Delivery::Base#deliver`), with an advisory early check at
`Onetime::Jobs::Publisher` so interactive callers get synchronous errors.

## Why now

Anyone with an account can put an arbitrary third-party address into a secret
link, an incoming secret, or an org invitation. Today there is no suppression
list, no bounce/complaint handling, no `List-Unsubscribe` header, no per-address
or per-domain limit, and no opt-out of owner notifications — every complaint and
every resend to a dead or hostile mailbox lands on the shared sending domains'
reputation. Gmail/Yahoo bulk-sender rules (Feb 2024) expect one-click
unsubscribe and complaint rates under 0.1%–0.3%; we currently have no mechanism
to stay under any threshold. The only outbound throttles anywhere are Rodauth's
30-second magic-link resend skip and the org-invitation `MAX_RESENDS = 3`.

## Grounding corrections

So implementers don't follow stale assumptions:

1. **There is no headers channel.** `Delivery::Base#normalize_email` whitelists
   exactly `to/from/reply_to/subject/text_body/html_body`; each of the four real
   backends (SMTP `::Mail`, SESv2 `content.simple`, SendGrid v3 JSON, Lettermint
   SDK fluent builder) builds its provider payload independently. RFC 8058
   headers require touching `Templates::Base#to_email`, `Mailer.deliver_raw`,
   `normalize_email`, the worker payload, AND all four backends (slice 10).
2. **`email.message.schedule` has no consumer.** Delayed messages rely on
   per-message TTL expiry dead-lettering into `dlq.email.message`, where
   `DlqEmailConsumerJob` replays only auth templates and **discards** the rest
   (including `expiration_warning`). Do not build anything on `schedule_email`
   until slice 61 fixes or retires it.
3. **Receipts store recipients obscured** (`recipients! eaddrs_safe_str` in
   `lib/onetime/models/receipt/features/deprecated_fields.rb`). Per-recipient
   send history cannot be reconstructed from Receipts; it must be recorded at
   send time (slice 20's event log).
4. **`Onetime::Utils::EmailHash` hard-requires `FEDERATION_SECRET`**, an
   optional env var. A suppression list must not inherit that availability
   coupling — see decision Q1.
5. **Publisher fallbacks bypass the worker.** When RabbitMQ is down or jobs are
   disabled (the self-hosted default), `:async_thread`/`:sync` fallbacks call
   `Onetime::Mail.deliver*` directly. Worker-only enforcement is insufficient;
   so is publisher-only (CLI `email send`, `Operations::Email::SendTest`,
   `Logic::Base#send_verification_email`, and DLQ replays skip the Publisher).
6. **The v0.23 `limit_action`/`OT::RateLimit` event system was never ported.**
   `src/schemas/contracts/config/section/limits.ts` (listing `email_recipient`)
   and `try/disabled/features/incoming/06_rate_limiting_try_disabled.rb` are
   vestiges — design against the `Onetime::Security::*RateLimiter` +
   `Operations::RateLimit::Registry` family instead.
7. **`BannedIP.banned?` is O(n)** (loads `ip_index.keys`, IPAddr-matches every
   entry). The send-path suppression check must be an O(1)
   `find_by_identifier`/EXISTS on the hash key — copy BannedIP's op/route/UI
   stack, not its lookup.
8. **Ops home is central.** `docs/specs/colonel-ui/44-email-ratelimit-tools.md`
   says "Ops home: apps/web/auth/operations/", but the shipped email, ratelimit,
   DLQ, banner, and ban ops all live in `lib/onetime/operations/` per decision
   D3 (the mailer is site-wide infrastructure). New verbs go in
   `lib/onetime/operations/email/` beside `send_test.rb`.

## Decisions (settle before Phase 0)

- **Q0 — No open/click tracking.** Bounce and complaint events only. Engagement
  tracking is contrary to the product's privacy posture and is a permanent
  non-goal, not a deferral.

- **Q1 — Hash key derivation.** Suppression entries, event logs, and rate-limit
  keys are keyed by an HMAC-SHA256 of the normalized address using a NEW
  `Onetime::KeyDerivation::PURPOSES` entry (`email_protection:`, env override
  `EMAIL_PROTECTION_SECRET`), derived from root `SECRET` per ADR-008 Category 1.
  Use `FEDERATION_SECRET` if present (optional, federation-scoped). DO NOT store
  plaintext addresses. Store the obscured display form
  (`OT::Utils.obscure_email`) alongside for admin UX. Normalization must be
  `OT::Utils.normalize_email` (strip → NFC → `downcase(:fold)`), same as
  `EmailHash`.

- **Q2 — Enforcement placement.** The authoritative gate is
  `Delivery::Base#deliver`, before `perform_delivery` — the same choke point as
  `record_sent_metric`, covering worker, fallbacks, direct senders, and DLQ
  replays. A second, advisory check in `Publisher#enqueue_email*` gives
  interactive callers synchronous rejection and saves queue traffic. A
  suppressed send is a SUCCESSFUL no-op (status `:suppressed`, ack'd, event
  logged) — never a raise inside the worker, never a DLQ entry.

- **Q3 — Category taxonomy.** Every outbound email carries a category
  (slice 10): `transactional_recipient` (third-party: secret_link,
  incoming_secret, organization_invitation, email_change_confirmation),
  `notification` (owner: secret_revealed, expiration_warning, and the dormant
  notification views), `transactional_account` (welcome/verify,
  password_request, magic_link + Rodauth raw, email_change_requested/changed,
  billing receipts, feedback), and `system` (test sends, diagnostics). The
  category drives suppression scope (slice 31 policy table) and which mail
  carries unsubscribe headers (`transactional_recipient` + `notification`).
- **Q4 — Token design.** Unsubscribe tokens are STATELESS, versioned HMAC
  tokens (payload: version ‖ category ‖ issued-at ‖ email-hash; key from the Q1
  purpose family) so links in year-old emails still work. Opt-back-in
  confirmation tokens are short-lived (24h expiry inside the signed payload).
  Do not use `Onetime::Secret` records as tokens (14-day TTL ceiling) and never
  put an address in a URL (`src/router/piiQueryGuard.ts` policy: opaque path
  tokens only).
- **Q5 — Limits are code constants in v1**, matching every existing
  `Onetime::Security` limiter, with the `force_enabled` test bypass and
  registry rows for admin inspect/reset. Operator-tunable config is a
  deliberate later step (it would be a new pattern; the vestigial `limits:`
  schema is the natural home if we ever need it).
- **Q6 — Opt-back-in is recipient-confirmed only.** Self-service resubscribe
  works for `unsubscribe`-reason entries via a double-confirm email loop.
  Complaint and hard-bounce entries are NOT self-service: complaint removal is
  CLI-only (the colonel-promotion precedent — the UI never lifts a complaint),
  hard-bounce removal is colonel-UI + CLI behind typed confirmation. Every
  removal is audited on EVERY invocation.


## Roadmap & dependency graph

**Phase 0 — Foundations:**
- [ ] [headers channel + email category taxonomy end-to-end](./10-headers-and-classification.md)
- [ ] [protection keys, address hashing, and stateless token format](./11-keys-hashing-tokens.md)

**Phase 1 — Suppression core:**
- [ ] [EmailSuppression model, event log, and the delivery gate](./20-suppression-model-and-gate.md)
- [ ] [suppression operations + CLI (check/add/remove/list/import)](./21-suppression-ops-and-cli.md)
- [ ] [colonel suppression endpoints + admin UI screen](./22-suppression-admin-ui.md)

**Phase 2 — Automatic feedback (the biggest reputation win):**
- [ ] [ESP webhook ingestion: endpoints, signature validation, idempotency, queue](./30-esp-webhook-ingestion.md)
- [ ] [bounce/complaint policy handlers writing suppressions](./31-bounce-complaint-handlers.md)

**Phase 3 — Outbound rate limits:**
- [ ] [per-address / per-domain / per-sender outbound email limits](./40-outbound-rate-limits.md)

**Phase 4 — Recipient controls:**
- [ ] [RFC 8058 one-click unsubscribe: headers, endpoints, landing page](./50-one-click-unsubscribe.md)
- [ ] [secure opt-back-in + guarded unsuppress](./51-opt-back-in.md)

**Phase 5 — Observability & cutover:**
- [ ] [delivery-health counters, thresholds, events console](./60-observability.md)
- [ ] [hardening & cutover: default-on, imports, PII cleanup, docs](./61-hardening-cutover.md)

Phase 0 blocks everything. 20 needs 10 (category on the wire) and 11 (hash
helper). 21/22 need 20. 30 needs 20 (something to write to); 31 needs 30. 40
needs 11 (hash keys) and 10 (category exemptions) but not Phase 2 — it can run
in parallel with 30/31. 50 needs 10, 11, and 20; 51 needs 50. 60 needs 20 and
30. 61 is last. If reputational pressure is acute, the shortest path to relief
is 10 → 11 → 20 → 30 → 31 (suppression fed by provider feedback), with 21 in
tow for operator access; 40 and 50 follow.

## Related prior art

- #3653 — Colonel Admin Rebuild epic: the Operations/adapters architecture,
  CONTRACT 4 (exactly-one audit per mutation), CONTRACT 6 (bounded reads), and
  decision D3 (ops placement) that every slice here inherits.
- `docs/specs/colonel-ui/44-email-ratelimit-tools.md` — shipped email
  template/test-send ops + ratelimit Registry/Inspect/Reset that slices 21/40
  extend.
- v0.23 PR #2538 — the old `limit_action :email_recipient` behavior;
  `try/disabled/features/incoming/06_rate_limiting_try_disabled.rb` is its
  spec-before-implement remnant that slice 40 supersedes.
- #2471 — cross-region email hashing (`Onetime::Utils::EmailHash`), the
  privacy-preserving key precedent behind decision Q1.
- ADR-008 — secret management architecture governing the new key purpose.
- `docs/architecture/custom-mail-sender.md`, `custom-mail-sender-ses.md`,
  `email-validation.md` — sender-domain provisioning and Truemail validation
  context these controls sit beside.

## Non-goals

- No marketing/newsletter email machinery — every message stays transactional
  or notification; no campaign concepts, no digest batching.
- No open/click tracking, ever (decision Q7).
- No live bidirectional suppression sync with providers — one-time/manual
  imports only (slice 61); the in-app list is the source of truth.
- No inbound SMTP DSN parsing for plain-SMTP installs in v1 — SMTP operators
  get manual suppression + import; document the limitation.
- No per-plan email quota entitlements in v1 — limits are site-wide constants
  (decision Q5); a billing-catalog entitlement is a separate future slice
  (`secrets_per_day` is already an unenforced stub — don't add a second one).
- Existing endpoint contracts unchanged; new endpoints only (self-hosted
  compatibility, same rule as #3653). The Zod schemas are the tripwire.
