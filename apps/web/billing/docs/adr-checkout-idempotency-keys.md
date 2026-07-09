---
status: accepted
title: "ADR: UUID Idempotency Keys for Checkout Session Creation"
---

## Status

Accepted

## Date

2026-07-09

## Context

Stripe deduplicates API calls by idempotency key: a request that reuses a key
within Stripe's retention window (24 hours) receives the *cached response* of
the first request, and reusing a key with *different parameters* raises
`Stripe::IdempotencyError`.

Checkout session creation used deterministic, time-bucketed keys:

- `BillingController#create_checkout_session` (API path):
  `SHA256("checkout:<orgid>:<plan_id>:<time>")` with **daily** granularity in
  live mode and per-minute granularity in test mode.
- `Plans#create_checkout_session` (redirect path):
  `"checkout_<extid>_<plan_id>_<minute>"` plaintext, per-minute.

This produced two production failure modes:

1. **Stale cached sessions.** A customer who completed (or abandoned) checkout
   and tried again the same day received the original session back. For a
   completed session, Stripe's hosted page shows "You're all done here"
   instead of a fresh checkout — the customer cannot subscribe again that day
   (e.g. after canceling, or after a failed payment attempt).
2. **Parameter-mismatch errors.** Changing anything inside the key's time
   bucket that alters the session parameters (locale, promotion settings,
   metadata) while org+plan stayed the same raised
   `Stripe::IdempotencyError: Keys for idempotent requests can only be used
   with the same parameters they were first used with`.

The root problem: deterministic keys treat session *creation* as the operation
that must be deduplicated. It is not. Creating a checkout session is a
pre-payment, side-effect-free operation — an unused session simply expires
(24h default). The operation that must not be duplicated is the *completion*
(subscription creation and charging), which is handled by the
`checkout.session.completed` webhook handler
(`operations/webhook_handlers/checkout_completed.rb`).

## Decision

**Checkout session creation uses a fresh `SecureRandom.uuid` idempotency key
per attempt.** Every request creates a new session; no attempt can receive a
cached prior session or collide with a prior key.

The key still serves a purpose at this narrower scope: it protects a *single*
HTTP call against network-level retries inside `Billing::StripeClient`'s
retry loop (`lib/stripe_client.rb` passes the same key to each retry of the
same logical call).

**Deterministic keys remain the correct choice for mutation calls**, where
retries of the same logical operation must collapse to one applied change:

- `BillingController#change_plan` keeps
  `SHA256("plan_change:<subscription_id>:<price_id>:<5-minute-window>")` for
  `Stripe::Subscription.update`. A duplicated plan-change request within the
  window is deduplicated by Stripe rather than applied twice.
- `Billing::StripeClient#generate_idempotency_key` (the fallback when no key
  is supplied) already used `"<timestamp>-<uuid>"` and is unchanged.

The dividing line: **random keys for idempotent-by-nature creations whose
duplicates are inert; deterministic time-windowed keys for mutations whose
duplicates would double-apply.**

## Consequences

- Rapid duplicate clicks or open tabs can now create multiple live checkout
  sessions. This is by design — sessions are free and expire — but it means
  session creation no longer provides any accidental guard against the same
  org completing two checkouts in one day. Duplicate-*completion* protection
  rests on:
  1. the frontend routing orgs with an active subscription to the
     plan-change flow instead of checkout (`PlanSelector.vue`), and
  2. the `checkout.session.completed` handler's idempotent replay check.

  Note the webhook check currently only skips replays of the *same*
  subscription (`org.stripe_subscription_id == subscription.id`); a second
  completed checkout producing a *different* subscription is applied and
  overwrites the first. That gap predates this change (the daily key only
  ever masked it on one of the two creation paths, within a single region and
  calendar day) and is tracked as follow-up hardening: a server-side guard at
  session creation (exempting currency-migration flows, which legitimately
  create a checkout while a `cancel_at_period_end` subscription is still
  active) and replacement detection in the webhook handler.
- Test-mode iteration no longer requires waiting out a one-minute bucket.
- VCR-based specs are unaffected: the key travels in the `Idempotency-Key`
  request header and cassettes match on method + URI.
