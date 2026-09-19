.. A new scriv changelog fragment.

Changed
-------

- The ``caddy_on_demand`` domain validation strategy now checks the domain's
  TXT challenge record before a custom domain counts as verified. Previously
  every verify pass under this strategy marked the domain verified without a
  DNS check. The rule is the same one the ``approximated`` strategy applies:
  exactly one TXT value at the validation record, equal to the challenge. The
  application performs the lookup itself, so it needs a working system
  resolver. Caddy obtaining a certificate is not treated as proof of
  ownership; the internal ACME endpoint continues to authorise certificates
  only for verified domains.

  **Upgrade note for self-hosted installs using** ``caddy_on_demand``: a
  domain that was marked verified without its TXT record loses verified status
  on the first domain refresh (or manual verify) after upgrading. While
  unverified, the ACME endpoint refuses new certificates for it, and
  features that require a verified domain (link creation under
  ``features.domains.require_verified``, domain sign-in and SSO) stop working
  for it. To keep a domain verified, either have its owner
  publish the TXT record shown on the domain's verification page, or set the
  verification override for that domain in the Colonel admin; an override
  holds verified through failed checks until it is removed or a check passes.
  A lookup that produces no answer (SERVFAIL, REFUSED, timeout) never changes
  stored state.

Fixed
-----

- Under the ``approximated`` strategy, a TXT record that has been removed now
  loses verified status even while Approximated's DNS checker returns no
  result. When the upstream check is indeterminate the application does its
  own lookup; a definitive answer from it (record found and matching, or
  NXDOMAIN / no TXT data / different values) is now used in both directions,
  where before it could only promote. A failed native lookup still leaves the
  domain as it was, and a Colonel override still holds verified.

Documentation
-------------

- ``apps/internal/acme/README.md`` no longer documents
  ``check_verification=false``. The ACME ask endpoint has ignored that
  parameter since it was removed from the HTTP interface; the README now
  matches.
