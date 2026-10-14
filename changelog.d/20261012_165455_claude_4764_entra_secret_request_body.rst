.. A new scriv changelog fragment.

Fixed
-----

- Microsoft Entra ID sign-in, for the platform registration and for custom
  domains, now sends the client ID and client secret in the token request
  body instead of the ``Authorization: Basic`` header. The header carried
  the raw ``id:secret`` pair without form-encoding, so a secret containing
  ``+`` or ``%`` could reach Entra altered and be refused as AADSTS7000215.
  Secrets now arrive byte for byte. No configuration change is needed.
  Generic OIDC and SAML are unchanged. (#4764)
