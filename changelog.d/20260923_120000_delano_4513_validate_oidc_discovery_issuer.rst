Changed
-------

- Install-wide OIDC sign-in now stops with a specific "misconfigured provider"
  message when ``OIDC_ISSUER`` differs from the discovery document's
  ``issuer``, logs both values as ``omniauth_install_issuer_mismatch``, and
  hides the provider from the sign-in page until the check is retried (except
  when sign-in is restricted to SSO). The comparison is exact, including any
  trailing slash. #4513
- Per-domain SSO Test Connection reports ``issuer_mismatch`` with the
  configured and discovered issuers for OIDC, and rejects discovery documents
  larger than 256 KiB. #4513
