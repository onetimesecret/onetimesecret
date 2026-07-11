---
labels: email-quality, phase-4, backend, frontend
depends: 10-headers-and-classification, 11-keys-hashing-tokens, 20-suppression-model-and-gate
epic: TBD
---

# Email quality: RFC 8058 one-click unsubscribe

## Context

Part of the **Email Quality Controls** epic, Phase 4. Every complaint is a
recipient who wanted a mute button and only found "Report spam". This slice
gives `transactional_recipient` and `notification` mail (decision Q3) the
compliant alternative: `List-Unsubscribe` + `List-Unsubscribe-Post:
List-Unsubscribe=One-Click` headers (RFC 8058, required by the Gmail/Yahoo
bulk-sender rules), a footer link, an unauthenticated POST endpoint that works
from the mail client's native button, and a human landing page.

## Scope

- **Token issuance**: at send time (`Templates::Base#to_email` for the two
  eligible categories), mint a non-expiring unsubscribe token
  (`EmailProtection::Token`, purpose `unsubscribe`, category + address hash in
  the payload — slice 11) and:
  - set `headers['List-Unsubscribe'] = '<https://<host>/unsubscribe/<token>>'`
    (and a `mailto:` alternative only if a route to ingest it exists — omit in
    v1 rather than advertise a dead letterbox),
  - set `headers['List-Unsubscribe-Post'] = 'List-Unsubscribe=One-Click'`,
  - expose `unsubscribe_url` to the ERB context for the footer link in
    `layout.html.erb` (sub-footer, beside `email.common.automated_notice`) and
    `layout.txt.erb`, rendered only for eligible categories.
  Host resolution follows the existing `baseuri`/`brand_baseuri` helpers —
  branded (custom-domain) mail links to the branded host.
- **Endpoints**:
  - `POST /api/v3/unsubscribe/:token` — `auth=noauth` Logic class (nil-`cust`
    safe), CSRF-exempt by the `/api/` prefix rule. RFC 8058: must succeed on
    the bare POST with no further interaction; body content ignored. Decodes +
    verifies the token, creates an `EmailSuppression` (reason `unsubscribe`,
    scope from category: `transactional_recipient` → `recipient_and_
    notification`, `notification` → `notification`), logs `unsubscribed`
    activity, returns 200. Idempotent: already-suppressed → 200. Invalid token
    → 404 after the rate-limit check.
  - `GET /unsubscribe/:token` — Core routes.txt `auth=noauth` line serving the
    SPA shell; Vue public route (`src/router/public.routes.ts`,
    TransactionalLayout) shows the obscured address + category, one confirm
    button POSTing the same endpoint, then a success state linking to the
    opt-back-in flow (slice 51). No locale is known for recipients (the queued
    `locale` is the SENDER's) — browser negotiation only.
- **Token abuse limiting**: per-IP invalid-token limiter
  (`InviteTokenRateLimiter` mold, e.g. 100/10min + lockout) so token structure
  can't be probed; registered in the ratelimit Registry.
- **Owner-notification coherence**: unsubscribing category `notification`
  where the address belongs to a customer also flips `notify_on_reveal` off
  (single source of truth for the user-visible toggle; account settings shows
  the same state). The suppression entry remains authoritative for
  non-customers.
- Locale keys `email.unsubscribe.*` + `web.unsubscribe.*` in
  `locales/content/en/` (fallbacks cover other locales until translated;
  content-hash workflow per TRANSLATION_PROTOCOL).

## Grounding — files & pointers

- Header/footer plumbing from slice 10; token codec from slice 11; suppression write from slice 20
- Layouts: `lib/onetime/mail/templates/layout.{html,txt}.erb`; ERB helpers in `lib/onetime/mail/views/base.rb` (`TemplateContext` — `baseuri`, `brand_baseuri`, `t`)
- noauth Logic precedents: `POST /api/v3/feedback` (`apps/api/v3/logic/feedback.rb` — per-IP limiter in `raise_concerns`), `POST /api/account/confirm-email-change` (token-style noauth flow; note it is a STATEFUL Secret token — ours is stateless per Q4)
- CSRF exemption: `/api/` prefix rule in `lib/onetime/middleware/security.rb`
- Public page precedents: `GET /feedback` + `GET /account/email/confirm/:token` in `apps/web/core/routes.txt`; Vue records in `src/router/public.routes.ts`; PII-in-URL policy `src/router/piiQueryGuard.ts` (opaque path tokens only)
- Preference precedent: `AccountAPI::Logic::Account::UpdateNotificationPreference` (`VALID_FIELDS = %w[notify_on_reveal]`), `Customer#notify_on_reveal?`
- Rate limiter mold: `lib/onetime/security/invite_token_rate_limiter.rb`

## Acceptance criteria

- [ ] Eligible mail carries BOTH headers on all four real backends and a
      working footer link; `transactional_account`/`system` mail carries
      neither.
- [ ] `curl -X POST .../api/v3/unsubscribe/<token>` with no cookies, no CSRF
      token, no body → 200 and the address stops receiving that category
      (RFC 8058 one-click semantics).
- [ ] GET landing never mutates (mail-client link prefetchers must not
      unsubscribe anyone — mutation on POST only).
- [ ] Tokens from mail sent BEFORE a category re-scope still verify (version
      byte honored); invalid tokens → 404 with per-IP limiter engaged.
- [ ] Response bodies never echo the plaintext address (obscured only) and
      never reveal prior suppression state distinctions (idempotent 200).
- [ ] Customer-notification unsubscribe reflects in account settings
      (`notify_on_reveal` false) and vice versa does NOT silently remove a
      suppression (settings re-enable goes through slice 51's confirm loop when
      a suppression exists).
- [ ] E2E: send secret_link via Logger backend in test → extract token from
      logged headers → POST → next send suppressed. Zod schemas for the JSON
      endpoint responses.

## Notes / risks

- One-click POST endpoints get hit by security scanners and link-checkers;
  idempotency + the invalid-token limiter make that harmless. GETs must stay
  side-effect-free for the same reason.
- The unsubscribe URL rides third-party-visible email; it must never embed the
  plaintext address (tokens carry the hash) — piiQueryGuard's policy extended
  to path design.
- `email_change_confirmation` is category `transactional_recipient` by Q3 but
  suppressing it can strand a legitimate email-change; acceptable — the
  in-product flow surfaces non-delivery generically, and the pending change
  expires. Called out so support recognizes the pattern.
- Branded hosts: the unsubscribe endpoint must be reachable on custom domains
  (same Core app serves them); token verification is host-independent.
