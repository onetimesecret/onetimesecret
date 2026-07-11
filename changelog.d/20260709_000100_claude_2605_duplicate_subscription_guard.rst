.. A new scriv changelog fragment.

Fixed
-----

- Checkout now blocks an organization that already owns a genuinely active,
  non-canceling subscription from starting a second checkout session (on
  both the API and plan-redirect paths), and the
  ``checkout.session.completed`` handler detects and loudly logs a completed
  checkout that would overwrite a *different*, still-active subscription.
  This closes a duplicate-subscription hazard — a double charge plus an
  orphaned, still-charging Stripe subscription — that could otherwise occur
  on rapid retries or multiple open tabs now that session creation uses
  per-attempt UUID idempotency keys. Currency-migration and
  resubscribe-after-cancel flows, where the prior subscription is winding
  down, remain exempt. (#2605)
