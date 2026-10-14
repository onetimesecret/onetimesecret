.. A new scriv changelog fragment.

Added
-----

- Generic OIDC can now be told how to send the client secret to the token
  endpoint: ``client_secret_basic`` (the ``Authorization: Basic`` header,
  the default) or ``client_secret_post`` (the request body). Custom domains
  choose it under Advanced in the SSO form, where Automatic keeps the
  default; the platform provider uses ``OIDC_CLIENT_AUTH_METHOD``. Existing
  configurations are unchanged. (#4764)
- SSO Test Connection now reports the token endpoint authentication methods
  the IdP advertises and warns when the selected method is not among them.
  (#4764)
