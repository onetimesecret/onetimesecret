.. A new scriv changelog fragment.

Added
-----

- The domain SSO settings show the outcome of the last sign-in through the
  domain: when it completed, or when it failed and at which step (before
  the identity provider, at the identity provider, on the way back, or
  when matching the user to an account) with the same code the visitor
  saw. The last completed sign-in is kept alongside a later failure. No
  identity or identity-provider text is stored; the record expires after
  90 days without a sign-in and is removed with the SSO configuration.
