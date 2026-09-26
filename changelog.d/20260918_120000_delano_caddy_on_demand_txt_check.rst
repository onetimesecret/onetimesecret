.. A new scriv changelog fragment.

Added
-----

- ``remove_orphaned_approximated_vhosts`` housekeeping chore, for installs
  that moved from the ``approximated`` validation strategy to another one.
  Changing the strategy deletes nothing on Approximated, so each domain keeps
  a billable virtual host there and the old vhost data on its record; the
  chore removes both. It is a dry run by default: it lists the deletion
  candidates and makes no Approximated API call. The nightly housekeeping job
  also runs it as a dry run. To delete, run it with the variable set::

      # Dry run (default)
      bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

      # Apply
      APPROXIMATED_VHOST_CLEANUP=apply bin/ots housekeeping run Onetime::CustomDomain remove_orphaned_approximated_vhosts

  Only the literal value ``apply`` deletes. Keep ``approximated.api_key`` and
  ``proxy_ip`` / ``proxy_host`` configured after the cutover: the chore needs
  the key to delete and the proxy address to tell which domains still point
  at the Approximated cluster. A virtual host is deleted only when the domain
  resolves to addresses outside the cluster and Approximated reports it as
  not resolving and not receiving traffic; everything else is skipped and
  picked up on a later run. ``verified``, ``resolving`` and the TXT fields
  are never changed. Details are in ``lib/onetime/domain_validation/README.md``.

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
  The record's host and value are shown to the domain's owner on the domain's
  verification page (see the next entry), on the Colonel domain detail page,
  in the output of ``bin/ots domains verify <domain>``, and as
  ``txt_validation_host`` / ``txt_validation_value`` in the domains API
  payload.

- The customer-facing domain pages now work under ``caddy_on_demand``. They
  previously showed the TXT challenge record, the status badge and the verify
  button only under ``approximated``, so under ``caddy_on_demand`` a customer
  had no way to learn which TXT record to publish. Both strategies now get
  the verification page: the TXT record's host and value, the verify button,
  and the status badge in the domain list and header. Adding a domain lands
  on that page and schedules the first check, as it does under
  ``approximated``. ``passthrough`` is unchanged and keeps the plain DNS
  setup page.

  Under ``caddy_on_demand`` the address record on that page points at this
  install: a CNAME (ALIAS/ANAME for an apex domain) to the canonical domain,
  falling back to the site host. The Approximated ``proxy_ip`` /
  ``proxy_host`` values are never shown under this strategy, even when they
  are still configured for the orphaned-vhost chore, and the Approximated DNS
  widget stays ``approximated``-only. The Colonel domain DNS panel shows the
  same address record as the customer pages; it previously showed the
  Approximated proxy targets under every strategy.

  The status badge has two new readings for the probe's ``PENDING_SSL``
  status (the name resolves, no certificate was seen). A verified domain
  reads "Certificate pending" and is not flagged as a problem: Caddy obtains
  the certificate on the first request after the TXT check passes. A domain
  whose TXT check has not passed reads "Pending Verification" and links to
  the verification page, because no certificate will be issued until it
  does. The same reading now applies, under both ``approximated`` and
  ``caddy_on_demand``, to an unverified domain whose status still says
  active (for example after its TXT record was removed while the certificate
  issued earlier keeps serving): it no longer reads "Active" and no longer
  gets the Manage quick action. "Unverified" is kept for a status check that
  failed.
  The SSL row of the status table reads "Unknown" rather than "Inactive" when
  the check could not tell. Under ``caddy_on_demand`` the table shows when the
  domain was last checked and leaves out the Approximated target address row.

  The verify button's feedback now follows what the TXT check found. The
  response of ``POST /api/domains/:extid/verify`` gains ``details.dns_outcome``
  (``validated``, ``indeterminate``, ``confirmation_expired``, ``failed`` or
  ``override_held``) and ``details.dns_indeterminate``. The success message is
  shown only for a matching record. A lookup that produced no answer says the
  check could not be completed and to try again, and a missing or different
  record says so; before, all three showed the same success message.

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
    The skip works inside one scheduler process. Scheduled jobs assume a
    single ``bin/ots scheduler`` per datastore, which is how the shipped
    compose file and S6 image run it; a second scheduler would repeat every
    refresh.
  - **Cutover from** ``approximated``: removing a domain under
    ``caddy_on_demand`` does not delete anything on Approximated
    (``delete_vhost`` is a no-op for this strategy), and neither does changing
    the strategy. Virtual hosts created while ``approximated`` was active stay
    there, billable and able to serve the hostname, until they are removed on
    the Approximated side: run the ``remove_orphaned_approximated_vhosts``
    chore (see Added above; a dry run unless
    ``APPROXIMATED_VHOST_CLEANUP=apply`` is set) with the Approximated API
    key still configured, or delete them in the Approximated dashboard.

    Sequence the switch so that proven domains keep verified.
    ``verified_confirmed_at`` is new in this version and is only written by a
    passing check on this version, so immediately after upgrading every
    domain has none, including domains Approximated had proven. Before
    changing the strategy: (1) upgrade while still on ``approximated`` and,
    still on ``approximated``, let one full refresh cycle complete on this
    version: either run ``bin/ots domains verify --all`` to the end (without
    ``--dry-run``, which records nothing), or let
    the domain refresh job walk every page (number of domains divided by
    ``batch_size``, times ``check_interval``). Every passing check, whether
    Approximated or the native lookup answered it, stamps
    ``verified_confirmed_at`` for that domain; (2) confirm
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
  already registered can no longer be added as a separate domain, or reached
  by renaming another one. Only the punycode form that is the encoding of the
  stored name matches it. A name that cannot be converted (an overlong label,
  malformed punycode) is answered with 403 by the ACME endpoint.

- ``features.domains.validation_strategy`` has always accepted any letter case
  and the aliases ``caddy`` and ``external``, but the configured spelling was
  sent to the frontend as written, which only recognises ``approximated``,
  ``caddy_on_demand`` and ``passthrough``. With ``caddy`` the domain pages
  therefore behaved as under ``passthrough`` (no TXT record, no verify
  button). The bootstrap payload and the domains API ``cluster`` now carry the
  canonical name of the strategy in effect.

Documentation
-------------

- ``apps/internal/acme/README.md`` no longer documents
  ``check_verification=false``. The ACME ask endpoint has ignored that
  parameter since it was removed from the HTTP interface; the README now
  matches.
