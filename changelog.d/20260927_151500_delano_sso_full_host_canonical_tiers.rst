.. A new scriv changelog fragment.

Fixed
-----

- SSO ``redirect_uri``, OAuth ``callback_url`` and the tenant SAML ACS URL
  and SP entity ID are now built from the same host resolver as
  transactional email links: the verified custom domain the request resolved
  to, then the request's own canonical host, then the configured
  ``site.host``. Previously any SSO request that was not on a verified custom
  domain took the raw ``Host`` header, so a proxy that sent a doubled
  ``Host: a, a`` produced an unregistered ``redirect_uri`` and the IdP
  rejected the login (#4517, reported in #4499). Two consequences of the
  shared resolver: a development browser on a host other than ``site.host``
  now gets its SSO URLs on ``site.host``, as its email links already did
  (set ``HOST`` to the host you browse); and a custom domain that is
  registered with SSO configured but not yet TXT-verified gets its
  ``redirect_uri`` / ACS URL on ``site.host``, which its IdP will reject
  until the domain is verified. Behind a Host-rewriting proxy that was
  already the case; it is new only where the ingress passes ``Host`` through
  unchanged. The auth log now records ``omniauth_tenant_domain_unverified``
  for that case. A ``site.host`` on a
  non-default port behind a doubling proxy still needs the proxy fixed: the
  port is read from the request authority, which cannot be parsed, so the
  URL carries the host but no port.
