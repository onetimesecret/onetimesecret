.. A new scriv changelog fragment.

Fixed
-----

- A paid-plan selection made before signup now survives the entire
  verified journey, including sign-ins that require a second factor
  (#4306). Previously an MFA-gated login consumed the pending plan intent
  at the primary factor — before the OTP was ever entered — and the MFA
  completion screen ignored it, so those users always landed on the
  dashboard instead of the selected plan.

- The pending plan intent is now consumed when the signed-in user actually
  reaches the billing plans page, not when the login response is built. A
  crash or transient failure between sign-in and the plans page no longer
  discards the selection permanently: the next sign-in within the 24-hour
  window retries the hand-off.

- The ``/billing/plans`` and ``/billing`` convenience routes no longer
  drop their query string when resolving to the organization-scoped
  billing pages, so ``?product=`` and ``?interval=`` reach the plan
  selector.
