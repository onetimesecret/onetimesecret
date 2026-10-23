.. A new scriv changelog fragment.

Added
-----

- The SAML SSO settings for a custom domain can fill the IdP SSO URL,
  EntityID and signing certificate from the identity provider's metadata
  URL. For Microsoft Entra ID, use the App Federation Metadata Url on the
  application's SAML page. The form lists every readable signing
  certificate the metadata publishes with its validity window, SHA-256
  fingerprint and the SHA-1 thumbprint the Entra portal shows, and the
  admin picks one. Certificates that cannot be read are left out with a
  warning. Nothing
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

Changed
-------

- A SAML EntityID that contains a template placeholder in braces, such as
  ``https://sts.windows.net/{tenantid}/`` from Entra's tenant-wide
  metadata, is refused when a domain SSO configuration is saved or tested,
  and a platform ``SAML_IDP_ENTITY_ID`` with one leaves the SAML provider
  off. Sign-in through such an EntityID failed at the issuer check. A
  configuration saved earlier with one can still be disabled, but not
  re-enabled or edited until the EntityID is replaced.
