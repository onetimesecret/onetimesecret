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

- The ``caddy_on_demand`` strategy now reports real resolving and SSL status
  for custom domains. Previously both were always unknown, so the domain
  pages never updated and a domain could not become ready without an operator
  setting ``resolving`` by hand. On each verify or domain refresh the
  application now looks up the domain's A/AAAA records and, if it resolves,
  completes a TLS handshake on port 443 and verifies the certificate for the
  hostname. No request is sent. The check refuses to connect to loopback,
  private, link-local or reserved addresses, and connects only to the address
  it resolved. A lookup or connection that fails on our side (SERVFAIL,
  timeout, no route) never changes stored state.

  **Upgrade notes for self-hosted installs using** ``caddy_on_demand``:

  - The application host needs outbound DNS and outbound TCP 443 to the
    custom domains it serves. Without it, status stays as it was and the
    domain pages show the last check as failed.
  - A domain becomes ready (and the internal ACME endpoint starts authorising
    its certificate) once its TXT record verifies and it has an A or AAAA
    record. A domain that stops resolving is no longer ready.
  - A domain whose names resolve only to private addresses is reported as
    resolving with SSL status unknown. A certificate from a private CA (for
    example ``tls internal``) is reported as no SSL, because it does not
    verify against the system trust store.
  - Domains that still carry vhost data from the ``approximated`` strategy
    keep showing it until the ``remove_orphaned_approximated_vhosts`` chore
    clears it; ``resolving`` is updated regardless.
  - With ``jobs.domain_refresh`` enabled, a page of domains that all time out
    takes much longer than before (up to 13s per domain). Lower
    ``batch_size`` if refresh runs overlap.

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
