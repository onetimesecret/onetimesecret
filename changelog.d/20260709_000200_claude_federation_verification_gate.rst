.. A new scriv changelog fragment.

Security
--------

- Federated subscription benefits are no longer claimed before an account's
  email is verified. Previously a pending cross-region subscription (matched
  by email hash) was claimed during standard email/password signup, before
  the verification email was even sent — letting someone who knew a
  subscriber's email register that email in another region and claim the
  subscriber's benefit. The claim is now deferred to ``after_verify_account``
  when email verification is enabled, and an unverified signup no longer
  computes an indexed email hash until it verifies. SSO (identity-provider
  verified), invite, and post-payment flows are unaffected.
