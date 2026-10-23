.. A new scriv changelog fragment.

Added
-----

- The SAML SSO settings for a custom domain can fill the IdP SSO URL,
  EntityID and signing certificate from the identity provider's metadata
  URL. For Microsoft Entra ID, use the App Federation Metadata Url on the
  application's SAML page. The form lists every signing certificate the
  metadata publishes with its validity window, SHA-256 fingerprint and the
  SHA-1 thumbprint the Entra portal shows, and the admin picks one. Nothing
  is saved until the admin applies the values and saves the form, which
  validates them as before. The metadata URL is stored with the
  configuration as the source of the imported values. Sign-in does not read
  it.
- ``POST /api/domains/:extid/sso/metadata`` fetches and parses the
  metadata without writing anything. The request goes through the same
  outbound guard as OIDC discovery. Each customer can make 30 requests per
  hour; the limit is set with ``SSO_METADATA_FETCH_RATE_LIMIT_ENABLED``,
  ``_MAX_PER_CUSTOMER``, ``_WINDOW`` and ``_LOCKOUT``
  (``features.organizations.sso_metadata_fetch_rate_limit``, limiter kind
  ``sso_metadata_fetch``).
