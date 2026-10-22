.. A new scriv changelog fragment.

Fixed
-----

- Passkey signup (``AUTH_WEBAUTHN_VERIFY_ACCOUNT=true``) with MFA on
  (``AUTH_MFA_ENABLED=true``) now verifies the account. Before this, the
  verification step answered with a server error and the account stayed
  unverified, because the recovery codes generated with the new passkey had
  no account to belong to yet. The codes now go to the account being
  verified, also when the browser still has a partly signed-in session for
  another account, which could receive them instead.
