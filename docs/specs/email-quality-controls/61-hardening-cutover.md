---
labels: email-quality, phase-5, backend, security, docs
depends: 30-esp-webhook-ingestion, 40-outbound-rate-limits, 50-one-click-unsubscribe, 60-observability
epic: TBD
---

# Email quality: hardening & cutover

## Context

Part of the **Email Quality Controls** epic, Phase 5 — the equivalent of
colonel Slice 6: flip defaults on, backfill, close the PII and infrastructure
loose ends the earlier slices routed around, and document the whole system for
operators and pentesters.

## Scope

- **Enforcement default-on**: `mail.suppression.enabled` ships `true`;
  self-hosted upgrade notes in `docs/migrating/` (behavior change: suppressed
  addresses silently stop receiving mail; new env vars; SES/SendGrid webhook
  setup pointers). Rate limiters were constants-on from slice 40; confirm
  ceilings against slice-60 data before release.
- **Backfill imports**: run `Suppression::Import` against current provider
  suppression lists (SES account-level suppression dump, SendGrid
  bounces/blocks/spam-reports exports) so day-one state matches provider
  reality. Document the export→import runbook per provider.
- **PII cleanup (pre-existing leaks this epic now owns)**:
  - `Operations::Dlq::Store.peek`'s `payload_preview` exposes plaintext
    recipient/sender addresses from failed email payloads in the colonel DLQ
    UI and CLI for up to 7 days — obscure emails in previews
    (`OT::Utils.obscure_email` pass over known payload fields before
    truncation).
  - Webhook idempotency records (slice 30) hold raw provider payloads: confirm
    the 5-day TTL and that no colonel surface renders them unredacted.
- **Schedule-queue decision** (grounding correction 2): `email.message.
  schedule` has no consumer, so delayed mail (today: `expiration_warning`)
  dead-letters and is discarded. Either (a) implement the missing consumer
  path (dead-letter routing back to `email.message.send` via
  `x-dead-letter-routing-key` on a versioned queue — queue arguments are
  immutable, so this is a `.v2` two-release migration), or (b) retire
  `schedule_email` and send expiration warnings directly with the job's own
  timing. Decide with real usage data; (b) is simpler and the epic's flows
  never use delays.
- **DLQ replay hygiene**: verify (tryout) that colonel DLQ replay and
  `DlqEmailConsumerJob` re-deliveries hit the slice-20 gate — suppression state
  at REPLAY time wins, not at original-send time. (True by construction with
  the Delivery-level gate; the tryout locks it.)
- **Docs**: `docs/operations/email-quality-controls.md` (operator guide:
  concepts, config keys, provider webhook setup, suppression workflows,
  health thresholds), `docs/runbooks/` entries (complaint-spike response;
  suppression check/release; import), pentest-scope addition for
  `/api/mail-events/*`, `/api/v3/unsubscribe/*`, `/api/v3/resubscribe/*`;
  cross-links from `docs/architecture/custom-mail-sender.md` and
  `email-validation.md`.
- **Changelog**: scriv fragments (`Added` for suppression/unsubscribe/limits,
  `Security` for webhook validation + PII cleanup) per `changelog.d/`
  conventions.

## Grounding — files & pointers

- Kill-switch + config: slice 20; defaults file `etc/defaults/config.defaults.yaml`
- Import op: slice 21 (`Suppression::Import`); provider dumps per SES/SendGrid docs
- DLQ preview leak: `lib/onetime/operations/dlq/store.rb` (`peek` → `payload_preview: payload.to_s[0..200]`, `safe_parse_payload`)
- Schedule-queue wiring: `lib/onetime/jobs/queues/config.rb` (`email.message.schedule`), `lib/onetime/jobs/publisher.rb` (`schedule_email`), `lib/onetime/jobs/scheduled/expiration_warning_job.rb`, `lib/onetime/jobs/scheduled/dlq_email_consumer_job.rb` (`discarded_non_auth`); versioned-queue migration strategy in `lib/onetime/jobs/queues/maintenance.md`
- Replay paths: `lib/onetime/operations/dlq/replay.rb`, colonel `ReplayDlq`
- Docs homes: `docs/operations/README.md`, `docs/runbooks/` (e.g. `feedback-rate-limit-verification.md` as runbook precedent), `docs/operations/pentest-scope.md`, `docs/migrating/`
- Changelog: `changelog.d/scriv.ini` + `changelog.d/README.md`

## Acceptance criteria

- [ ] Fresh install with only root `SECRET`: suppression, unsubscribe, and
      limits all function (no optional-secret dependency — Q1 verified
      end-to-end).
- [ ] Upgrade notes published; `bin/ots config validate` passes on a default
      config with the new sections.
- [ ] Provider suppression backfill runbooks executed against staging; import
      idempotency re-verified on the real dumps.
- [ ] DLQ peek shows obscured addresses in previews (CLI + colonel),
      byte-for-byte otherwise.
- [ ] Schedule-queue decision made, implemented, and `DlqEmailConsumerJob`'s
      discard behavior re-documented to match.
- [ ] Replay-time suppression tryout green.
- [ ] Pentest scope updated; operator guide + runbooks merged; scriv fragments
      present.

## Notes / risks

- Backfill imports are bulk PII handling — staging first, delete export files
  after, note retention in the runbook.
- Flipping suppression default-on changes behavior for self-hosted operators
  who never configure webhooks: their list only grows via manual/CLI entries
  and unsubscribes, which is safe — but say it in the migration notes.
- The DLQ preview fix touches golden-mastered CLI output — update the masters
  deliberately in the same PR, calling out the intentional break.
