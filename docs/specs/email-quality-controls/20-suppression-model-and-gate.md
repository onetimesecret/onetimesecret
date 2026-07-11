---
labels: email-quality, phase-1, backend
depends: 10-headers-and-classification, 11-keys-hashing-tokens
epic: TBD
---

# Email quality: EmailSuppression model, event log, and the delivery gate

## Context

Part of the **Email Quality Controls** epic, Phase 1 — the core capability.

This slice creates the suppression store and wires enforcement into the send
path per decision Q2: a hard gate at `Delivery::Base#deliver` (covers worker,
publisher fallbacks, CLI direct sends, SendTest, and DLQ replays — 100% of
outbound mail) plus an advisory check at `Publisher#enqueue_email*` (synchronous
caller UX, less queue traffic). It also creates the per-address event log that
replaces the send history Receipts can't provide (grounding correction 3).

## Scope

- **Model `Onetime::EmailSuppression`** (`lib/onetime/models/email_suppression.rb`,
  registered in `lib/onetime/models.rb`), shaped on
  `Billing::PendingFederatedSubscription`:
  - `prefix :email_suppression`, `identifier_field :email_hash` (idempotent
    last-write-wins; O(1) `find_by_identifier` — grounding correction 7).
  - Fields: `email_hash`, `email_obscured` (display only), `reason`
    (`REASONS = %w[hard_bounce soft_bounce complaint unsubscribe manual]`),
    `scope` (`SCOPES = %w[all recipient_and_notification notification]` —
    policy table in slice 31), `source` (ses/sendgrid/lettermint/webhook/
    admin/cli/recipient/import), `note`, `created`/`updated`
    (`feature :required_fields`).
  - `feature :expiration` with NO class default; per-instance TTL for
    soft-bounce entries only (slice 31); hard_bounce/complaint/unsubscribe/
    manual entries are permanent.
  - Class API: `suppressed?(email_hash, category:)` — single-lookup predicate
    applying scope-vs-category semantics; `suppress!(...)` idempotent create;
    `release!(email_hash)`.
  - `feature :safe_dump` + `SCHEMA` constant (colonel UI lists it — slice 22).
- **Event log `Onetime::EmailActivity`**: Horreum keyed by `email_hash` with a
  per-instance capped `sorted_set :events` (member `"kind:ms:nonce"` + JSON
  detail, cap 100, `remrangebyrank` — the `Receipt::AccessTimeline` shape) plus
  a global capped `class_sorted_set :recent` (AdminAuditEvent shape,
  trim-on-write, MAX 10_000) for the admin feed. Kinds: `sent`, `suppressed`,
  `hard_bounce`, `soft_bounce`, `complaint`, `unsubscribed`, `resubscribed`.
  Fail-open writes (a logging failure never breaks a send). Detail carries
  template, category, provider — never subjects/bodies/plaintext addresses.
- **Gate**: in `Delivery::Base#deliver`, after `normalize_email`, compute
  `EmailProtection.address_hash(email[:to])` and consult
  `EmailSuppression.suppressed?(hash, category: email[:category])`. Suppressed
  → log event, increment counter, return a suppressed-status response object
  (like `Disabled`'s `status: 'skipped'`) WITHOUT calling `perform_delivery`.
  Config kill-switch `mail.suppression.enabled` (default true once shipped;
  slice 61 flips) checked via boot-time runtime state, not per-send `OT.conf`
  digs.
- **Advisory check** in `Publisher#enqueue_email`/`enqueue_email_raw`: when the
  recipient is suppressed for the category, skip publish, log, return a
  distinguishable falsy/status result. Callers that want to surface it (e.g.
  secret conceal with recipient) can message the sender WITHOUT confirming
  suppression state to them — return generic "could not be delivered" phrasing
  (an existence oracle for suppression is an information leak; see the
  recipient-disclosure spec's no-oracle principle).
- **Counters**: `Onetime::Customer.class_counter :emails_suppressed` beside
  `emails_sent` at the same choke point.
- Config: `mail.suppression.enabled` key in `etc/defaults/config.defaults.yaml`
  (+ Zod contract in `src/schemas/contracts/config/section/mail.ts`, shape,
  `pnpm run schemas:json:generate` — config is deep-frozen at boot, so runtime
  state lives in Redis; config carries only the flag).

## Grounding — files & pointers

- Choke point + metric precedent: `lib/onetime/mail/delivery/base.rb` (`deliver`, `normalize_email`, `record_sent_metric`)
- Enqueue funnel: `lib/onetime/jobs/publisher.rb` (`enqueue_email`, `enqueue_email_raw`, fallbacks `FALLBACK_STRATEGIES`)
- Worker semantics (suppressed ≠ failure): `lib/onetime/jobs/workers/email_worker.rb` — suppressed results must `ack!`, never `reject!`/DLQ
- Model shape precedent: `apps/web/billing/models/pending_federated_subscription.rb` (identifier_field :email_hash, feature :expiration, PII/NOT-PII field partition)
- Event log precedents: `lib/onetime/models/admin_audit_event.rb` (capped class ZSET, fail-open) and `lib/onetime/models/receipt/features/access_timeline.rb` (per-entity capped timeline)
- Blocklist stack precedent (op/route/UI to copy, lookup NOT to copy): `apps/api/colonel/models/banned_ip.rb`
- Model registration/load order: `lib/onetime/models.rb`
- Config pipeline: `etc/defaults/config.defaults.yaml`, `src/schemas/contracts/config/section/mail.ts`, `lib/onetime/operations/config/validate.rb`
- DLQ replay paths that make the Delivery-level gate mandatory: `lib/onetime/operations/dlq/replay.rb`, `lib/onetime/jobs/scheduled/dlq_email_consumer_job.rb`

## Acceptance criteria

- [ ] A suppressed address receives NOTHING via: queued send, `:sync`/
      `:async_thread` fallback, `bin/ots email send`, colonel test send
      (reports `:suppressed` status), DLQ replay, DlqEmailConsumerJob.
- [ ] Scope semantics honored: an `unsubscribe`-reason entry blocks
      `transactional_recipient`/`notification` but a password reset
      (`transactional_account`) still delivers; a `hard_bounce` entry blocks
      everything.
- [ ] Suppressed queue messages are ack'd with an event logged — DLQ depth does
      not grow; `EmailWorker` retry logic never engages for suppression.
- [ ] Gate adds exactly one O(1) Redis lookup per send; no SCAN/KEYS
      (CONTRACT 6).
- [ ] `emails_suppressed` counter increments; `emails_sent` does NOT count
      suppressed sends.
- [ ] Sender-facing API responses do not reveal whether a recipient is
      suppressed (generic phrasing, same shape as success where the flow allows).
- [ ] Tryouts: end-to-end suppress → send → no delivery + event logged, against
      real Valkey; RSpec: scope matrix, kill-switch off restores delivery,
      fail-open event-log write.

## Notes / risks

- ⚠️ Do NOT raise from the gate inside the worker path — a raise classifies as
  a delivery failure, engages retries, and dead-letters mail that must simply
  not be sent. Status object, not exception.
- The obscured display form is stored at suppress time because it cannot be
  recovered from the hash later; suppression created from a webhook uses the
  provider-supplied address before discarding it.
- `EmailSuppression` and `EmailActivity` writes happen inside the delivery
  path — keep them one round-trip each and fail-open (AdminAuditEvent
  precedent) so Redis blips degrade to "sent without logging", never "blocked".
- Multi-tenancy: entries are GLOBAL (platform reputation is shared). Per-org
  scoping is deliberately out of scope for v1; the `source`/`note` fields keep
  provenance for support.
