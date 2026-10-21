.. A new scriv changelog fragment.

Fixed
-----

- Passkey signup (``AUTH_WEBAUTHN_VERIFY_ACCOUNT=true``) with email
  verification otherwise off (``AUTH_VERIFY_ACCOUNT_ENABLED=false``) now
  completes the verification on the application side: the customer record
  is marked verified, a federated subscription pending for the address is
  claimed at verification rather than at signup, the branded verification
  email is sent, and the resend-verification endpoint is available. Before
  this, only the auth database row changed and the customer stayed
  unverified. The auth config exposes the combined condition as
  ``verify_account_loaded?``.
