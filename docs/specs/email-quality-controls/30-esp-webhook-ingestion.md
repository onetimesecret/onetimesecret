---
labels: email-quality, phase-2, backend, security
depends: 20-suppression-model-and-gate
epic: TBD
---

# Email quality: ESP webhook ingestion (endpoints, validation, idempotency, queue)

## Context

Part of the **Email Quality Controls** epic, Phase 2 — the largest reputation
win: the providers already KNOW which addresses bounce and complain; we just
never listen. This slice clones the proven Stripe pipeline
(controller-with-raw-body → signature validator → idempotency record → enqueue
→ worker → operation with a handler registry) for the three API providers.
Slice 31 supplies the handlers; this slice delivers verified, deduplicated
events onto a queue.

## Scope

- **New app `apps/api/mail_events/`** (`MailEventsAPI::Application`,
  `@uri_prefix = '/api/mail-events'`): subclasses `Onetime::Application::Base`
  DIRECTLY — NOT `BaseJSONAPI` — so no `Rack::JSONBodyParser` touches the body
  before signature verification (the billing-app property). Auto-mounted by the
  registry. Controller-style route targets (Logic classes never see the Rack
  request):
  - `POST /webhooks/:provider` → `MailEventsAPI::Controllers::Webhooks#handle_event`
    (provider ∈ frozen allowlist `%w[ses sendgrid lettermint]`; unknown → 404).
  Mounting under `/api/` makes the endpoint CSRF-exempt via the existing
  `allow_if` prefix rule — no `lib/onetime/middleware/security.rb` edit needed.
- **Per-provider validators** (`apps/api/mail_events/lib/validators/`):
  - `ses`: SNS envelope handling — auto-confirm `SubscriptionConfirmation`
    (fetch SubscribeURL only after validating it is `https` on an
    `sns.<region>.amazonaws.com` host), verify SNS message signatures
    (SigningCertURL pinned to the AWS SNS cert domain, signature over the
    canonical string), then parse the inner SES event JSON. ⚠️ SNS posts with
    `Content-Type: text/plain` — another reason the body must be read raw.
  - `sendgrid`: Signed Event Webhook — ECDSA verify
    `X-Twilio-Email-Event-Webhook-Signature` over timestamp+payload with the
    configured public key; enforce a max event age (Stripe's `MAX_EVENT_AGE`
    tolerance pattern).
  - `lettermint`: verify per Lettermint's webhook signing scheme (confirm
    against current docs/SDK at implementation time — treat "docs unclear" as
    a blocker, never skip verification).
  - Missing/invalid signature or unconfigured secret → 401/400/500 exactly per
    the Stripe controller's semantics.
- **Idempotency model `Onetime::EmailProviderEvent`** (clone
  `Billing::StripeWebhookEvent`): `identifier_field :event_key`
  (`"<provider>:<provider_event_id>"`), `default_expiration 5.days`, state
  machine pending→success/failed/retrying with `attempt_count`. Duplicates and
  permanently-failed events return **200** (silence provider retries); enqueue
  failure returns **500** (provider retries).
- **Queue** `email.event.process` + `dlx.email.event`/`dlq.email.event` in
  `QueueConfig::QUEUES`/`DEAD_LETTER_CONFIG` (follows `{domain}.{entity}.
  {action}`; queue arguments are immutable — get it right first time).
  `Publisher.enqueue_mail_provider_event(...)` with the billing dual-mode
  fallback: synchronous op execution when jobs are disabled, raise (→500) when
  the broker is down.
- **Worker** `lib/onetime/jobs/workers/email_event_worker.rb`
  (Sneakers + BaseWorker, `claim_for_processing`, `with_retry`) delegating to
  `Onetime::Operations::Email::ProcessProviderEvent` (slice 31).
  `check_essentials!` validates configured webhook secrets.
- Config under `mail.webhooks.{ses,sendgrid,lettermint}` (enabled flags +
  provider verification material: SendGrid public key, Lettermint secret, SES
  expected TopicArn allowlist) — ERB'd defaults + Zod contract/shape + schema
  regen. Webhook secrets follow the `billing_config.webhook_signing_secret`
  precedent.

## Grounding — files & pointers

- Pipeline to clone: `apps/web/billing/controllers/webhooks.rb`, `apps/web/billing/lib/webhook_validator.rb`, `apps/web/billing/models/stripe_webhook_event.rb`, `apps/web/billing/workers/billing_worker.rb`
- App mounting: `lib/onetime/application/registry.rb` (globs `apps/**/application.rb`); smallest standalone app `apps/api/incoming/application.rb`; controller-style base `apps/web/billing/controllers/base.rb`
- CSRF allowlist behavior: `lib/onetime/middleware/security.rb` (`/api/` prefix exempt; `/billing/webhook` literal precedent)
- Queue topology + immutability: `lib/onetime/jobs/queues/config.rb`, `declarator.rb`, `lib/onetime/jobs/queues/maintenance.md`; add-a-queue workflow in `lib/onetime/jobs/README.md`
- Publisher dual-mode fallback: `Publisher.enqueue_billing_event` in `lib/onetime/jobs/publisher.rb`
- Worker template: `lib/onetime/jobs/workers/base_worker.rb` (+ `email_worker.rb`)
- Provider identities (which webhooks matter): `lib/onetime/mail/delivery/{ses,sendgrid,lettermint}.rb`; Lettermint bounce CNAME config in `etc/defaults/config.defaults.yaml` `email_providers:`

## Acceptance criteria

- [ ] Signature verification is mandatory per provider; a request with a
      missing/invalid signature never reaches parsing; secrets absent →
      endpoint returns 500 without processing (Stripe semantics).
- [ ] Raw body reaches the validator byte-identical (no JSONBodyParser in the
      app stack); SNS `text/plain` posts verify.
- [ ] Duplicate provider events (same event_key) return 200 without
      re-enqueueing; replay attacks outside the timestamp tolerance are
      rejected.
- [ ] SES SubscriptionConfirmation auto-confirms only for allowlisted
      TopicArns and https SNS-domain URLs; everything else logged + dropped.
- [ ] Queue declared with DLX; worker discovered by `bin/ots worker` with zero
      registration code; jobs-disabled installs process synchronously.
- [ ] Shared-example security specs mirroring
      `apps/web/billing/spec/support/shared_examples/webhook_security.rb`.
- [ ] Payloads (which contain plaintext recipient addresses) are never logged
      whole; log obscured addresses + event types only.

## Notes / risks

- These are the first UNAUTHENTICATED endpoints that mutate email-delivery
  state — the validators are the security boundary; add the routes to
  `docs/operations/pentest-scope.md` in slice 61.
- SES setup requires operator action (configuration set → event destination →
  SNS topic → HTTPS subscription). Ship a `docs/operations/` how-to alongside;
  the endpoint works but is inert until wired on the provider side.
- SMTP-mode installs get nothing from this slice — that limitation is stated
  in the epic non-goals and the operator docs.
- Provider event payloads may include full recipient addresses and message
  headers: hash + obscure at the earliest parse point, keep the raw payload
  only inside the idempotency record (5-day TTL), and never surface it in
  colonel DLQ previews (see slice 61's PII cleanup).
