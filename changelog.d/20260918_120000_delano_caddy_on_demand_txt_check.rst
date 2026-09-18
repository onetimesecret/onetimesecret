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
  A lookup that produces no answer (SERVFAIL, REFUSED, timeout) leaves stored
  state alone, within the confirmation window described below.

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
    takes much longer than before (up to 13s per domain). Refresh runs no
    longer overlap: a tick that fires while the previous run is still working
    is skipped, and its page is picked up on the next walk. Lower
    ``batch_size`` if runs routinely take longer than ``check_interval``.
  - **Cutover from** ``approximated``: removing a domain under
    ``caddy_on_demand`` does not delete anything on Approximated
    (``delete_vhost`` is a no-op for this strategy), and neither does changing
    the strategy. Virtual hosts created while ``approximated`` was active stay
    there, billable and able to serve the hostname, until they are removed on
    the Approximated side: run the ``remove_orphaned_approximated_vhosts``
    chore with the Approximated API key still configured, or delete them in
    the Approximated dashboard.

- A verified domain whose TXT checks stop producing an answer is no longer
  held verified indefinitely. The first indeterminate check of a verified
  domain starts a 7-day confirmation window; any definitive answer ends it. If
  a check is still indeterminate once the window has run out, the domain loses
  verified status. The outcome is reported as ``confirmation_expired`` in the
  Colonel verify response and notice, in ``bin/ots domains verify`` output
  (``Expired`` in the bulk summary, ``confirmation_expired_count`` and
  ``issue_details.dns_expired`` in JSON), in the domain refresh summary line,
  and in a warning log line. The window runs from the first indeterminate
  check, not from the last passing one, so a single failed lookup never
  demotes a domain however long ago it was last checked. Nothing is demoted at
  upgrade: existing domains have no window until their first indeterminate
  check. A Colonel override exempts a domain, and a demoted domain becomes
  verified again on its next passing check. ``CustomDomain`` gains two fields,
  ``verified_confirmed_at`` and ``verified_unconfirmed_since``.

- The pause between domains in a bulk verify now comes from the validation
  strategy: 0.5s under ``approximated`` (its API rate cap), none under
  ``caddy_on_demand`` and ``passthrough``. ``jobs.domain_refresh.rate_limit``
  no longer has a default; leave it unset to use the strategy's pacing, or set
  any number, including 0, to override it. ``bin/ots domains verify --all``
  follows the same rule for ``--rate-limit``. Installs whose config file sets
  ``rate_limit: 0.5`` explicitly keep that pause under every strategy.

Fixed
-----

- Under the ``approximated`` strategy, an indeterminate provider TXT check now
  falls back to the application's DNS resolver. A matching local answer can
  verify the domain, and a negative local answer keeps a never-verified domain
  unverified. One local negative no longer revokes an existing verification by
  itself; a definitive negative from Approximated still does.

Documentation
-------------

- ``apps/internal/acme/README.md`` no longer documents
  ``check_verification=false``. The ACME ask endpoint has ignored that
  parameter since it was removed from the HTTP interface; the README now
  matches.
