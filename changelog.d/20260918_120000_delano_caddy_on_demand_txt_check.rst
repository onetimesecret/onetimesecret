.. A new scriv changelog fragment.

Changed
-------

- The ``caddy_on_demand`` domain validation strategy now checks the domain's
  TXT challenge record before a custom domain counts as verified. Previously
  every verify pass under this strategy marked the domain verified without a
  DNS check. The rule is the same one the ``approximated`` strategy applies:
  exactly one TXT value at the validation record, equal to the challenge. The
  application performs the lookup itself, so it needs a working system
  resolver. An internationalised hostname is looked up in its punycode form.
  Caddy obtaining a certificate is not treated as proof of
  ownership; the internal ACME endpoint continues to authorise certificates
  only for verified domains.

  **Upgrade note for self-hosted installs using** ``caddy_on_demand``: a
  domain that was marked verified without its TXT record loses verified status
  the first time it is checked after upgrading. While unverified, the ACME
  endpoint refuses new certificates for it, and features that require a
  verified domain (link creation under
  ``features.domains.require_verified``, domain sign-in and SSO) stop working
  for it. To keep a domain verified, either publish its TXT record or set the
  verification override for that domain in the Colonel admin; an override
  holds verified through failed checks until it is removed or a check passes.
  The record's host and value are shown on the Colonel domain detail page, in
  the output of ``bin/ots domains verify <domain>``, and as
  ``txt_validation_host`` / ``txt_validation_value`` in the domains API
  payload. The customer-facing domain pages do not show the TXT record or a
  verify button under this strategy yet (they do under ``approximated``), so
  the operator has to pass the record on to the domain's owner and run the
  verify.

  Existing domains are only re-checked when something runs the check. The
  scheduler is off by default (``JOBS_ENABLED``), and without it and
  ``jobs.domain_refresh`` no refresh ever runs: domains marked verified
  without a TXT record then stay verified, and verified on its own still
  gates link creation under ``require_verified``, domain sign-in and SSO.
  Installs that do not run the domain refresh job must run
  ``bin/ots domains verify --all`` once after upgrading for the TXT check to
  take effect on existing domains, and periodically after that (for example
  from cron) so that a removed record is noticed.

  A lookup that produces no answer (SERVFAIL, REFUSED, timeout) leaves stored
  state alone, within the confirmation window described below. The exception
  is a verified domain that no TXT check has ever confirmed, which is every
  verified domain on this strategy at upgrade: it has no earlier proof to
  protect, so an unanswered lookup also withdraws verified. It becomes
  verified on the next check that finds the record. A Colonel override holds
  it here as well.

  The same applies to a domain verified under ``passthrough``. That strategy
  passes every domain without a DNS check, so its passes are stored in
  verified but are not recorded as a TXT confirmation
  (``verified_confirmed_at`` stays empty). After a move from ``passthrough``
  to ``caddy_on_demand`` such a domain stays verified only once a check finds
  its TXT record, or under a Colonel override.

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

    Sequence the switch so that proven domains keep verified.
    ``verified_confirmed_at`` is new in this version and is only written by a
    passing check on this version, so immediately after upgrading every
    domain has none, including domains Approximated had proven. Before
    changing the strategy: (1) upgrade while still on ``approximated`` and
    run a full ``bin/ots domains verify --all`` pass (or let the domain
    refresh job complete a walk of every page), which records the
    confirmation for each domain whose TXT record is in place; (2) confirm
    the application host has a working resolver (nameservers in
    ``resolv.conf``, outbound DNS allowed), because ``caddy_on_demand`` is
    the first time the application does the TXT lookup itself on every
    check. If the strategy is switched without this, a first lookup under
    ``caddy_on_demand`` that gets no answer (no nameserver configured, DNS
    egress blocked, SERVFAIL, timeout) withdraws verified from a domain that
    Approximated had proven, and link creation under ``require_verified``,
    domain sign-in and SSO stop working for it until the next passing check
    or a Colonel override.

- A verified domain whose TXT checks stop producing an answer is no longer
  held verified indefinitely. The first indeterminate check of a verified
  domain starts a 7-day confirmation window; any definitive answer ends it. If
  a check is still indeterminate once the window has run out, the domain loses
  verified status. The outcome is reported as ``confirmation_expired`` in the
  Colonel verify response, notice and audit event, in ``bin/ots domains verify`` output
  (``Expired`` in the bulk summary, ``confirmation_expired_count`` and
  ``issue_details.dns_expired`` in JSON), in the domain refresh summary line,
  and in a warning log line. The window runs from the first indeterminate
  check, not from the last passing one, so a single failed lookup never
  demotes a domain however long ago it was last checked. The window demotes
  nothing at upgrade: existing domains have no window until their first
  indeterminate check (for ``caddy_on_demand`` see the upgrade note above). A
  Colonel override exempts a domain, and a demoted domain becomes
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

- Under the ``approximated`` strategy, a TXT check that could not reach
  Approximated at all (no API key configured, a non-200 response, a network
  error) is no longer reported as a failed check. The application does its
  own lookup in those cases too, so a domain whose record is in place is
  confirmed, a removed record is noticed, and only a domain whose native
  lookup also produces no answer is reported as indeterminate and falls under
  the 7-day confirmation window. An install whose Approximated API key is
  missing or revoked keeps its domains verified through the native lookup. An
  unexpected error during a verify is likewise reported as indeterminate
  rather than failed.

- An internationalised custom domain that was entered in Unicode (for example
  ``bücher.example``) is now found when it is looked up by its punycode form
  (``xn--bcher-kva.example``), and the other way round. Caddy asks the
  internal ACME endpoint about the punycode name and browsers send it in the
  Host header, so such a domain was refused a certificate under
  ``caddy_on_demand`` and was not recognised as a custom domain on incoming
  requests. Stored domains are not changed. The second form of a name that is
  already registered can no longer be added as a separate domain. A name that
  cannot be converted (an overlong label, malformed punycode) is answered with
  403 by the ACME endpoint.

Documentation
-------------

- ``apps/internal/acme/README.md`` no longer documents
  ``check_verification=false``. The ACME ask endpoint has ignored that
  parameter since it was removed from the HTTP interface; the README now
  matches.
