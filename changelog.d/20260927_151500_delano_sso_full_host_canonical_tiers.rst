.. A new scriv changelog fragment.

Fixed
-----

- Fixed SSO and transactional email URLs behind proxies that send a doubled
  ``Host`` header. URLs now use the verified custom domain or a configured
  canonical host, including its configured non-default port, instead of the
  malformed request authority (#4517, reported in #4499).

- Tenant SSO is now offered only after custom-domain ownership is verified.
  Until verification, sign-in surfaces withhold the provider and SAML service
  provider identifiers instead of advertising a flow that cannot complete.
