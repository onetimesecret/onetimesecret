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
- ``/auth`` responses now send ``Cache-Control: private, no-store`` by
  default. #4461
- Colonel ``PUT /api/colonel/domains/:extid/configs/signin`` answers ``422``
  for a ``related_origins`` entry owned by another organization (it used to
  answer ``200`` for an entry that never took effect), and a first write now
  stores ``related_origins`` instead of silently dropping it. #4421

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
  ``active_session_revoked``. Full authentication mode only: simple mode has
  no such row.
- Repeated verification failures no longer sign the user out.
- A failing log sink during an OmniAuth callback without a Connect intent no
  longer reclassifies an ordinary SSO sign-in as a refused Connect. #4431

Security
--------

- The raw session id is no longer written to the session store's log lines
  or the sign-in/sign-out lines of the Web Core authentication controller; a
  logged id could be replayed as the cookie. #4461

Documentation
-------------

- New ``docs/authentication/customer-session-failure-matrix.md``: every
  session state on every surface, the refusal code each produces, and what
  to capture when a user reports being signed out. #4452

AI Assistance
-------------

- Implemented and reviewed with Claude across planning, backend, frontend
  and browser-test stages. The first real browser run found two defects the
  unit suites could not: the bootstrap schema rejected every real server
  payload, and ``GET /logout`` could be undone by an in-flight request.
