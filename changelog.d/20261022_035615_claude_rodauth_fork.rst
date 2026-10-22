.. A new scriv changelog fragment.

Fixed
-----

- Passkey signup (``AUTH_WEBAUTHN_VERIFY_ACCOUNT=true``) with MFA on
  (``AUTH_MFA_ENABLED=true``) now verifies the account. Before this, the
  verification step answered with a server error and the account stayed
  unverified. Rodauth now comes from the onetimesecret fork
  (onetimesecret/rodauth#3), which adds the recovery codes generated with
  the new passkey to the account being verified, also when the browser
  still has a partly signed-in session for another account, and deletes
  the verification key once the account is verified instead of replacing
  it with a new one.
