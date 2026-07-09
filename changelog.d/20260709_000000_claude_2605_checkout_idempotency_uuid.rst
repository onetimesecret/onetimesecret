.. A new scriv changelog fragment.

Fixed
-----

- Checkout session creation now sends a fresh UUID idempotency key on every
  attempt instead of a deterministic time-bucketed key (daily in live mode,
  per-minute in test mode). Customers who retried checkout within the same
  window previously received Stripe's cached — possibly already-completed —
  session ("You're all done here"), and same-window requests with changed
  session parameters raised ``Stripe::IdempotencyError``. Duplicate
  *completions* remain deduplicated by the ``checkout.session.completed``
  webhook handler; mutation calls such as plan changes keep their
  deterministic 5-minute-window keys so retries still collapse to one applied
  change. See ``apps/web/billing/docs/adr-checkout-idempotency-keys.md``.
  (#2605)
