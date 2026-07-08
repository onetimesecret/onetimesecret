---
labels: email-quality, phase-4, backend, frontend, security
depends: 50-one-click-unsubscribe
epic: TBD
---

# Email quality: secure opt-back-in + guarded unsuppress

## Context

Part of the **Email Quality Controls** epic, Phase 4. People unsubscribe by
accident, complaints get filed by overzealous filters, and mailboxes come back
to life — there must be a way back that CANNOT be driven by the same third
party who caused the mail in the first place. Decision Q6: opt-back-in is
recipient-confirmed double opt-in for `unsubscribe`-reason entries; complaint
removal is CLI-only; hard-bounce removal is admin-guarded. The impersonation
convention from colonel Slice 6 applies: explicit operation, audited on EVERY
invocation.

## Scope

- **Recipient self-service flow** (unsubscribe-reason entries only):
  1. Entry points: the unsubscribe success page (slice 50) and
     `GET /resubscribe/:token` (same non-expiring unsubscribe token — the
     recipient possesses it in their old mail).
  2. `POST /api/v3/resubscribe/:token` (`auth=noauth`) — verifies the token,
     checks the entry is reason `unsubscribe` (anything else → generic "cannot
     be undone here" copy, no state disclosure), then sends ONE confirmation
     email: new template `resubscribe_confirmation`, category
     `suppression_recovery` — a fifth category whose ONLY member is this
     template and which the slice-20 gate allows through an
     unsubscribe-scoped suppression (still blocked by `hard_bounce`
     `all`-scope entries). Hard-capped at 1 per address per 24h
     (`email:limit:resub:%s`, Registry-registered).
  3. The confirmation email carries a SHORT-LIVED confirm token
     (`EmailProtection::Token`, purpose `resubscribe_confirm`, 24h expiry).
     `POST /api/v3/resubscribe/confirm/:token` → re-verify entry state (a
     complaint/bounce recorded meanwhile wins — slice 31 note), release the
     suppression via the op below, log `resubscribed` activity, 200.
- **Op `Onetime::Operations::Email::Suppression::Release`** — the single
  implementation behind recipient confirm, colonel remove (slice 22), and CLI
  remove (slice 21); parameters `actor:` (`'recipient'` sentinel for the
  self-service path — precedent: `CLI_ACTOR = 'cli'`), `via:`
  (`recipient_confirm/colonel/cli`), policy matrix enforced HERE not in
  adapters:

  | Entry reason | recipient confirm | colonel UI | CLI |
  |---|---|---|---|
  | unsubscribe | ✅ | ✅ | ✅ |
  | soft_bounce | ✅ (implicit: TTL usually beats them to it) | ✅ | ✅ |
  | hard_bounce | ❌ | ✅ typed-confirm | ✅ |
  | complaint | ❌ | ❌ | ✅ `--allow-complaint` |
  | manual | ❌ | ✅ typed-confirm | ✅ |

  Stricter-than-CONTRACT-4 audit rule (the Slice-6 impersonation convention):
  `Release` records an `AdminAuditEvent` (`email.suppression.release`) on
  EVERY invocation that reaches the policy check — including refusals
  (`result: :refused`) — because unsuppression is the abuse-sensitive verb in
  this system.
- **Account-settings coherence**: a customer re-enabling `notify_on_reveal`
  while a `notification`-scope suppression exists on their address triggers
  the same confirm-email loop instead of silently flipping the flag (the
  suppression is authoritative; slice 50 established the pairing).
- Vue: resubscribe page states (request sent / confirmed / cannot-undo-here),
  obscured address only; locales `web.resubscribe.*`.

## Grounding — files & pointers

- Token codec + purposes: slice 11; suppression model + gate categories: slice 20; ops family + CLI flag: slice 21; colonel adapter: slice 22
- Audit-on-every-invocation convention: `docs/specs/colonel-ui/52-impersonation-audit-fix.md`
- Colonel-promotion-stays-CLI-only precedent (for complaint removal): `docs/specs/colonel-ui/50-cutover-hardening.md`
- noauth token endpoints + limiter: slice 50's endpoints; `lib/onetime/security/invite_token_rate_limiter.rb`
- Template registration: `Mailer.template_class_for` (`lib/onetime/mail/mailer.rb`) + view in `lib/onetime/mail/views/`; sample fixture in `lib/onetime/mail/samples/` for preview tooling
- Preference toggle: `AccountAPI::Logic::Account::UpdateNotificationPreference`

## Acceptance criteria

- [ ] A third party who triggers unsubscribe mail CANNOT complete opt-back-in
      without mailbox access: release requires the confirm token that only
      arrives IN the suppressed mailbox.
- [ ] Confirmation email is the only mail that passes an unsubscribe-scope
      suppression; it is still blocked for hard-bounced addresses; 1/24h cap
      enforced and Registry-visible.
- [ ] Expired confirm tokens (>24h) fail closed; re-requesting works next day.
- [ ] Policy matrix enforced in the op — colonel API cannot release a
      complaint entry even with a hand-crafted request; CLI requires the
      explicit flag.
- [ ] EVERY `Release` invocation audits (success, refusal, not-found), actor
      correctly `'recipient'`/extid/`'cli'`.
- [ ] Responses never distinguish "no entry" from "entry you may not release"
      to unauthenticated callers (no-oracle rule).
- [ ] Tryout: full loop — unsubscribe → resubscribe request → confirm →
      delivery restored; RSpec: policy matrix + meanwhile-complaint race.

## Notes / risks

- The `suppression_recovery` category is a tempting bypass channel — its
  membership is a frozen one-element list, asserted in spec; adding to it
  requires touching this policy deliberately.
- Send the confirmation email immediately via `enqueue_email`; there is no
  delayed-send path (`schedule_email` and the `email.message.schedule` queue are
  removed in slice 61, grounding correction 2).
- Refusal copy must be generic ("this address's status can't be changed here;
  contact support") — naming the reason would disclose complaint state to
  whoever holds the token.
