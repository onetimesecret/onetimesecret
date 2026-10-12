.. A new scriv changelog fragment.

Fixed
-----

- Tenant SSO email-domain allowlists now treat the Unicode and A-label forms
  of an internationalised domain as the same domain. An allowlist entry typed
  as ``bücher.de`` no longer denies an IdP that asserts
  ``user@xn--bcher-kva.de``, and the reverse. Entries are still stored and
  shown as typed. Sign-ins that match only because the forms differed are
  logged as ``omniauth_tenant_domain_idn_match``. A Unicode entry that has no
  exact A-label form is now rejected when the SSO configuration is saved.
  (#4736)
