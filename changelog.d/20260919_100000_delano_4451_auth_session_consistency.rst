.. A new scriv changelog fragment.

Added
-----

- Bootstrap payloads (page hydration and ``GET /bootstrap/me``) now state the
  session in one field, ``auth_status`` (``authenticated``, ``anonymous``,
  ``mfa_pending`` or ``unavailable``). ``authenticated`` and ``awaiting_mfa``
  are derived from it and can no longer disagree. Payloads that report a
  session also carry ``snapshot_epoch``, ``snapshot_version`` and
  ``snapshot_generated_at`` so a browser tab can refuse a snapshot older than
  the one it holds (ADR-046). #4462, #4457
- JSON ``401`` responses for a refused session carry ``code`` (for example
  ``active_session_revoked``, ``stale_credentials``, ``admin_session_expired``)
  and ``code_scope`` (``customer_session``, ``verification_unavailable`` or
  ``admin_session``). Status codes, redirects and existing body fields are
  unchanged. #4462
- A client may mark a timer-driven ``GET`` or ``HEAD`` with the request header
  ``X-Session-Activity: passive``. The request is authenticated and answered
  as usual and moves no inactivity clock, exactly like the
  ``GET /bootstrap/me`` poll. The header is ignored on ``POST``, ``PUT``,
  ``PATCH`` and ``DELETE`` and can only shorten the sender's own session. The
  dashboard's receipt lists use it for their 5-minute and tab-visibility
  refreshes, so a tab left on the dashboard now signs out on schedule. A proxy
  that strips unknown request headers turns those refreshes back into
  activity and breaks nothing else. #4455
- Two log lines: ``Bootstrap verification`` (Session logger, info; one per
  authenticated ``/bootstrap/me`` poll, with query and write counts) and
  ``Session refused`` (Auth logger; carries the ``code``, the request id and
  the route pattern, never a session id or the request path). #4455, #4461

Changed
-------

- An idle signed-in tab now really reaches the inactivity deadline.
  ``GET /bootstrap/me`` is verified in full but no longer counts as activity:
  it does not move the active-session row's ``last_use``, the admin idle
  bound or the session's TTL. Before this release the 15-minute poll kept an
  untouched tab signed in indefinitely. A request that a session gate refused
  does not count as activity either. #4455
- A page load makes no ``/bootstrap/me`` request when the server-rendered
  payload is valid (previously at least one per load). Expect a visible drop
  in that endpoint's traffic. A page whose payload is missing or invalid
  makes exactly one request instead of rendering as signed out. #4456
- When the server cannot be reached to verify the session, protected pages
  show "We can't verify your session right now" with a retry button after
  three failed attempts. The user is not signed out and recovery needs no
  page load. #4460
- A session that ended, was revoked, or was replaced by another sign-in
  outside a tab reloads that tab once and shows one message. If a secret is
  being typed the browser asks before leaving. Rotating the application
  secret changes every ``snapshot_epoch``, so each open signed-in tab reloads
  once at its next refresh. #4464, #4465
- ``GET /bootstrap/me`` can answer ``503`` with ``Retry-After: 5`` when a
  signed-in payload cannot be given a snapshot version (datastore trouble).
  Clients retry; an ended session is still reported as ``200`` anonymous.
  #4457
- Session store log lines carry ``session_handle`` instead of ``session_id``,
  and ``redis_key`` is gone. Any log query, alert or dashboard keyed on
  ``session_id`` for these lines must change. #4461
- ``LOG_HTTP_CAPTURE=debug`` request lines carry ``session_handle`` as well;
  no log line writes a session id any more. #4461
- An ordinary duplicate sign-up logs ``registration_blocked_existing_account``
  at info. ``registration_blocked_auth_db_conflict`` (error) is now logged only
  when the auth database has the account and the datastore has no customer
  record for it, which is what its hint always described. Alerts on that
  event will fire far less often.
- A session cookie naming an id the server holds no session for is given a new
  id instead of keeping the one it presented (stock Rack behaviour). Signing
  out also removes the session's ``session_metadata:<id>`` key instead of
  leaving it to expire.
- ``/auth`` responses now send ``Cache-Control: private, no-store`` by
  default. #4461
- Every response under ``/api`` that sets no cache policy of its own now sends
  ``Cache-Control: private, no-store``. The API sent no ``Cache-Control``
  before. Confirm no intermediary overrides it. #4470
- Under ``RACK_ENV=test`` diagnostics (Sentry) stay off unless
  ``DIAGNOSTICS_ENABLED_IN_TEST=true`` is set as well, and the server that
  Playwright starts itself is given ``DIAGNOSTICS_ENABLED=false``. A test
  server booted from a developer's shell no longer reports to the Sentry
  project that shell points at. No other environment changes.
- Protected pages, page hydration, ``GET /bootstrap/me``, protected APIs and
  the ``/auth`` routes now decide from one shared customer-session verdict, so
  they can no longer disagree about whether a session is valid. #4453, #4454
- Deploy the backend and the frontend of this release together. Each half
  tolerates the other's previous version only in a degraded form, and a
  rolling deploy with mixed workers can reload a signed-in tab once. See
  ``docs/authentication/session-consistency-rollout.md``. #4463

Deprecated
----------

- ``had_valid_session`` in the bootstrap payload. Nothing reads it; removal is
  tracked in #4468.

Fixed
-----

- ``GET /logout`` now removes the session's active-session row, as
  ``POST /auth/logout`` already did. A request still in flight during the
  logout could write the whole session back and hand the browser its old
  cookie again, leaving the user signed in; that copy is now refused as
  ``active_session_revoked``.
- A request in flight while its session is ended (logout, or a session revoked
  from the sessions page or by an operator) can no longer write the session
  back, in either authentication mode. Ending a session leaves a 5-minute
  marker (``ended_sid:<digest>`` in the datastore, never the session id), and a
  session write that finds it is discarded and sends no cookie.
- Concurrent sign-ups against a SQLite auth database no longer answer ``500``
  (``database is locked``). Writers now wait for each other. A sign-up that
  loses a race for its email address answers exactly like an ordinary
  duplicate sign-up, on SQLite and PostgreSQL; it used to answer ``422`` with
  "already an account with this login". A sign-up for an existing *unverified*
  account now answers ``400`` like one for a verified account; it answered
  ``403``, which told a caller the account's state.
- ``/auth`` answers ``503`` with ``Retry-After: 1`` (``error_type:
  AuthDatabaseBusy``) when the auth database is saturated: a SQLite write lock
  held past the 5-second wait, or no free pooled connection. It answered a
  generic ``500``. Migration connections use the same SQLite wait settings as
  request connections.
- After signing out or switching accounts in the same tab, the custom-domain
  list could stay empty until a forced refresh.
- The colonel console shows a refused ``allowed_signup_domains`` entry under
  that field. ``PUT /api/colonel/domains/:extid/configs/signup`` answers the
  ``422`` with ``field`` and ``error_key``
  (``api.domains.errors.allowed_signup_domains_invalid``), as the
  ``related_origins`` refusals already do.
- ``apps/web/core/templates/error.rue`` did not parse, so its hydration schema
  was never generated. The template and ``Core::Views::Error`` are removed:
  nothing has rendered them since error pages moved to the Vue entry point.
- Repeated verification failures no longer sign the user out.
- Opening ``/recent`` directly showed an empty list: the receipt list only
  loaded if the dashboard had been visited first. The dashboard's 5-minute
  status refresh, which never sent a request, now runs.

Security
--------

- The raw session id is no longer written to the session store's log lines,
  the sign-in, sign-out and password-reset lines, or any ``/auth`` event line
  (``[before_logout]``, ``[after_logout]``, unhandled exceptions); a logged id
  could be replayed as the cookie. These lines carry ``session_handle``.
  #4461
- A session that has presented a password but not its second factor can no
  longer read ``/auth/account``, list or remove active sessions, list SSO
  identities or passkeys, or start a re-authentication. It reaches only the
  challenge routes, ``GET /auth/mfa-status`` and logout, and is answered
  ``401`` with ``code: awaiting_mfa`` elsewhere. Closes
  ``RISK-2026-08-13-02`` in the security risk register. #4453

Documentation
-------------

- New ``docs/authentication/customer-session-failure-matrix.md``: every
  session state on every surface, the refusal code each produces, and what
  to capture when a user reports being signed out. #4452
- New ``docs/authentication/session-consistency-rollout.md``: deployment
  notes for this release and the signals to check on staging. #4463
- Security records: ``docs/security/audits/security-audit-2026-09-19.md``
  reviews this package, the risk register closes ``RISK-2026-08-13-02`` and
  gains four low-rated entries. This release closes three of them
  (``RISK-2026-09-19-01``, ``-03`` and ``-04``); ``RISK-2026-09-19-02``
  (no session id renewal when the second factor completes) stays open,
  tracked by #4466.
