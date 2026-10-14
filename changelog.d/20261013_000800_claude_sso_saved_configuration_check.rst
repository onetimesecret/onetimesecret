.. A new scriv changelog fragment.

Added
-----

- The domain SSO form has a "Check saved configuration" section that checks
  the stored record layer by layer: the saved fields, the identity
  provider's discovery document (OIDC, Entra ID), the saved IdP certificate
  (SAML), and, for Entra ID, whether Microsoft accepts the saved client
  secret. Each layer reports passed, failed or inconclusive separately, so
  a wrong or expired secret (AADSTS7000215, AADSTS7000222) is named rather
  than inferred from a failed sign-in. The secret, any token and Microsoft's
  error description never reach the response. Runs are capped per customer
  (10 per hour by default; ``SSO_DIAGNOSTICS_RATE_LIMIT_*``).
- The Entra ID client secret field warns when the entered value is shaped
  like a Secret ID (a UUID) rather than the secret Value.
