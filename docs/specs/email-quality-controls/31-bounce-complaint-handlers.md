---
labels: email-quality, phase-2, backend
depends: 30-esp-webhook-ingestion
epic: TBD
---

# Email quality: bounce/complaint policy handlers

## Context

Part of the **Email Quality Controls** epic, Phase 2. Slice 30 delivers
verified, deduplicated provider events onto `email.event.process`; this slice
turns them into suppression entries and activity-log writes under one explicit
policy table, via the self-registering handler-registry shape
(`Billing::Operations::ProcessWebhookEvent` precedent).

## Scope

- `Onetime::Operations::Email::ProcessProviderEvent.new(event:, context: {}).call`
  (central, `lib/onetime/operations/email/process_provider_event.rb`) —
  normalizes each provider's payload into a common internal event
  (`provider, kind, recipient, subtype, timestamp, diagnostic`), then
  dispatches over a class-level registry auto-populated by
  `handlers/base_handler.rb`'s `inherited` callback; handlers answer
  `.handles?(kind)` and return `:success/:skipped/:unhandled`.
- **Provider event mapping** (normalize BEFORE policy):
  - SES: `Bounce` (bounceType `Permanent` → hard; `Transient`/`Undetermined` →
    soft), `Complaint` → complaint. One SES message may carry multiple
    recipients — fan out per recipient.
  - SendGrid: `bounce` → hard; `blocked`/`deferred` → soft; `dropped` with
    reason "bounced address"/"spam report address" → treat as
    provider-side-suppressed (mirror as hard/complaint); `spamreport` →
    complaint. Ignore `processed/delivered/open/click` (Q7).
  - Lettermint: map its bounce/complaint vocabulary at implementation time
    against current docs (same hard/soft/complaint buckets).
- **Policy table** (the heart of the slice; constants in one module so slice 60
  and the docs cite a single source):

  | Event | Action | Reason | Scope | TTL |
  |---|---|---|---|---|
  | hard bounce | suppress immediately | `hard_bounce` | `all` | none (permanent) |
  | soft bounce | count; suppress after `SOFT_BOUNCE_THRESHOLD = 3` distinct events within `SOFT_BOUNCE_WINDOW = 72h` | `soft_bounce` | `all` | `SOFT_BOUNCE_TTL = 14 days` |
  | complaint | suppress immediately | `complaint` | `recipient_and_notification` | none (permanent) |

  Scope semantics (with slice 20's categories): `all` blocks everything
  including `transactional_account`; `recipient_and_notification` blocks
  `transactional_recipient` + `notification` but lets the recipient's OWN
  account-security mail (password reset, email-change notices) through —
  a complaint about a share shouldn't lock a customer out of account recovery,
  while a dead mailbox blocks everything. `notification` scope is reserved for
  category-scoped unsubscribes (slice 50).
- Soft-bounce counting: fixed-window Redis counter keyed by address hash
  (`emailquality:softbounce:%s`), Lua INCR+EXPIRE, same mechanics as the
  Security limiters; counter co-located with the suppression model's dbclient.
- Every handled event writes `EmailActivity` (kind, provider, template if the
  provider echoes our category/message metadata) — fail-open.
- Suppress writes go through `EmailSuppression.suppress!` (idempotent;
  escalation rule: a complaint or hard bounce UPGRADES an existing softer
  entry — wider scope/longer TTL wins; never downgrades).
- These are recipient-caused mutations, not admin actions: NO
  `AdminAuditEvent` per event (CONTRACT 4 actors are admins); the activity log
  is the record. A daily aggregate line in logs keeps operators aware.

## Grounding — files & pointers

- Handler registry precedent: `apps/web/billing/operations/process_webhook_event.rb` + `operations/webhook_handlers/{base_handler,…}.rb` (self-registration via `inherited`, `Dir[...].each { require }` tail)
- Suppression API: slice 20's `EmailSuppression.suppress!` / `EmailActivity`
- Counter mechanics: `lib/onetime/security/feedback_rate_limiter.rb` (Lua INCR + EXPIRE window), key sanitization in `lib/onetime/security/dns_rate_limiter.rb`
- Transient/fatal classification vocabulary already in the backends: `lib/onetime/mail/delivery/ses.rb` (`TRANSIENT/FATAL_ERROR_CODES`), `sendgrid.rb` (status-code classes) — keep the webhook mapping consistent with it
- Worker + op wiring: slice 30's `EmailEventWorker`

## Acceptance criteria

- [ ] Policy table implemented exactly as specced, thresholds as frozen
      constants; a hard bounce blocks a subsequent password reset, a complaint
      does not.
- [ ] Soft-bounce escalation: 3 events in-window creates a 14-day entry; the
      window resets on expiry; a later hard bounce upgrades it to permanent
      `all`.
- [ ] Escalation never downgrades (complaint entry survives a later soft
      bounce).
- [ ] Multi-recipient SES bounces fan out; per-recipient idempotency holds when
      a provider re-delivers the same event (slice 30's event_key + idempotent
      `suppress!`).
- [ ] Open/click/delivered events are dropped unprocessed (Q7) — asserted in
      spec.
- [ ] Unknown event kinds return `:unhandled`, are logged (obscured), ack'd —
      never DLQ'd (a new provider event type must not poison the queue).
- [ ] RSpec: policy matrix + mapping fixtures per provider (recorded sample
      payloads under `spec/fixtures/`); tryout: end-to-end SES hard bounce →
      suppressed send.

## Notes / risks

- Fixture payloads must be sanitized samples, never production captures.
- SES `Undetermined` bounces are noisy — bucketing them as soft (not hard) is
  deliberate; revisit with real data via slice 60's counters.
- Providers retry webhooks aggressively; everything here must stay idempotent
  under at-least-once delivery from BOTH the provider and RabbitMQ.
- If a provider event arrives for an address currently mid-opt-back-in
  (slice 51), the new suppression simply wins — the confirm step re-checks
  state before releasing.
