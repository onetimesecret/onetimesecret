---
labels: email-quality, phase-0, backend
depends: none
epic: TBD
---

# Email quality: headers channel + category taxonomy end-to-end

## Context

Part of the **Email Quality Controls** epic, Phase 0 — the plumbing every later
slice stands on.

Two gaps: (1) the canonical email hash (`to/from/reply_to/subject/text_body/
html_body`) has no way to carry custom headers, so `List-Unsubscribe` /
`List-Unsubscribe-Post` (slice 50) cannot reach a provider; (2) no send knows
what KIND of email it is, so suppression scoping (slice 31) and unsubscribe
eligibility (decision Q3) have nothing to key on. This slice adds an optional
`headers:` hash and a required `category:` string to the email envelope and
threads both through every hop: template → publisher payload → worker → mailer
→ backend.

## Scope

- Extend `Onetime::Mail::Templates::Base#to_email` to emit `category:` (from a
  per-template class macro, e.g. `category :transactional_recipient`) and an
  empty-by-default `headers: {}`.
- Extend `Mailer.deliver_raw`'s normalized hash, `Publisher.enqueue_email` /
  `enqueue_email_raw` payloads, `EmailWorker#deliver_email`, and
  `Delivery::Base#normalize_email` to carry both fields losslessly. Unknown
  category defaults to `transactional_account` (fail-safe: most-protected,
  least-unsubscribable class).
- Map `email[:headers]` in all four real backends: SMTP via
  `mail_message['Header-Name'] = value`; SESv2 via `content.simple.headers`
  (`[{name:, value:}]` — verify the pinned aws-sdk-sesv2 supports it, else
  `content: {raw:}` fallback); SendGrid v3 top-level `headers` object;
  Lettermint via the SDK's header support (verify against the vendored gem —
  ⚠️ if the SDK exposes no header API this is a blocker to raise, not to
  silently drop).
- Assign categories to all 11 registered templates + `magic_link` per decision
  Q3; Rodauth raw mail is tagged `transactional_account` at the
  `auth.send_email` hook (`apps/web/auth/config/email/delivery.rb`) since raw
  payloads have no template identity downstream.
- Bump `QueueConfig::CURRENT_SCHEMA_VERSION` handling only if needed: additive
  optional fields should NOT require a version bump — in-flight V1 messages
  (no category) must keep delivering during deploy.

## Grounding — files & pointers

- Envelope construction: `lib/onetime/mail/views/base.rb` (`Templates::Base#to_email`)
- Normalization whitelist: `lib/onetime/mail/delivery/base.rb` (`normalize_email`)
- Raw path: `lib/onetime/mail/mailer.rb` (`deliver_raw`), `apps/web/auth/config/email/delivery.rb`
- Queue payloads: `lib/onetime/jobs/publisher.rb` (`enqueue_email`, `enqueue_email_raw`); consumer `lib/onetime/jobs/workers/email_worker.rb` (`deliver_email` — reads both symbol/string keys defensively)
- Backends: `lib/onetime/mail/delivery/{smtp,ses,sendgrid,lettermint}.rb` (`build_mail_message` / `build_email_params` / `build_payload` / `perform_delivery`)
- Template registry (category assignment checklist): `Mailer.template_class_for` in `lib/onetime/mail/mailer.rb:180-207`; dormant views in `lib/onetime/mail/views/` get categories as they're wired
- Schema versioning: `lib/onetime/jobs/queues/config.rb` (`CURRENT_SCHEMA_VERSION`, `Versions`)

## Acceptance criteria

- [ ] Every registered template class declares a category; `to_email` output
      includes it; a template without one fails loudly in test, defaults safely
      in production.
- [ ] `headers:` set on an email hash arrives at the provider on all four real
      backends (integration-test SMTP with the mail gem; stub-verify the three
      API backends' request payloads).
- [ ] Rodauth raw emails carry `category: transactional_account` through
      `enqueue_email_raw` → worker → `deliver_raw`.
- [ ] In-flight pre-deploy queue messages (no category/headers) still deliver;
      fallback paths (`:sync`, `:async_thread`) carry the fields identically.
- [ ] `Logger` backend prints category + headers so tryouts can golden-master
      them; `Disabled` backend unaffected.
- [ ] No behavior change to any existing email's content or routing — this
      slice is pure plumbing.

## Notes / risks

- The Rodauth `send_email` hook flattens multipart `Mail::Message`s and drops
  any headers Rodauth set — that stays true; OUR fields are added to the
  wrapper payload, not extracted from the Mail object.
- SESv2 simple-content header support depends on SDK version; check
  `Gemfile.lock` before choosing simple-headers vs raw-MIME. Raw-MIME changes
  DKIM signing inputs for SES — prefer simple-headers if available.
- Category strings are a frozen closed set (`Onetime::Mail::CATEGORIES`
  constant, `%w[transactional_recipient transactional_account notification
  system]`) with fail-closed fallback — mirror `Receipt::SOURCES` style.
