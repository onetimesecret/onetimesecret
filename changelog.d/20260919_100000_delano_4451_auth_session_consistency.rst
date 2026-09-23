.. A new scriv changelog fragment.

Added
-----

- Bootstrap payloads now expose a single ``auth_status`` and versioned snapshot
  metadata, allowing browser tabs to reject stale authentication state. #4457,
  #4462
- JSON ``401`` responses for refused sessions now include stable ``code`` and
  ``code_scope`` fields. Existing status codes, redirects, and body fields are
  unchanged. #4462
- Clients can mark timer-driven ``GET`` and ``HEAD`` requests with
  ``X-Session-Activity: passive`` so they do not extend the sender's inactivity
  deadline. The header is ignored for state-changing requests. #4455

Changed
-------

- Idle dashboard tabs now sign out at the configured inactivity deadline;
  background refreshes and refused requests no longer keep sessions active.
  #4455
- Pages use valid server-rendered authentication state without an initial
  ``GET /bootstrap/me`` request. If session verification is temporarily
  unavailable, protected pages retry without signing the user out. #4456, #4460
- Tabs reload once and show a message when their session ends, is revoked, or
  is replaced elsewhere. The browser asks before leaving when a secret is being
  edited. #4464, #4465
- ``GET /bootstrap/me`` can return ``503`` with ``Retry-After: 5`` when session
  state cannot be verified; clients retry automatically. #4457
- Session-related logs now use ``session_handle`` instead of ``session_id`` and
  no longer include ``redis_key``. Update affected log queries, alerts, and
  dashboards. #4461
- ``/auth`` responses and API responses without their own cache policy now send
  ``Cache-Control: private, no-store``. Confirm that intermediaries do not
  override this policy. #4461, #4470
- Protected pages, bootstrap payloads, protected APIs, and authentication routes
  now use the same customer-session verdict. #4453, #4454
- Deploy this release's backend and frontend together. Mixed-version rolling
  deployments can briefly degrade session handling and reload a signed-in tab.
  See ``docs/authentication/session-consistency-rollout.md``. #4463

Deprecated
----------

- The bootstrap payload field ``had_valid_session`` is deprecated and scheduled
  for removal in #4468.

Fixed
-----

- Logout and session revocation now prevent in-flight requests from restoring
  an ended session or its cookie.
- Colonel now shows ``allowed_signup_domains`` validation failures against the
  correct field and includes field-specific error details in the API response.
- Repeated session-verification failures no longer sign the user out.

Security
--------

- Raw session IDs have been removed from authentication and session-store logs
  because they could be replayed as session cookies. Use ``session_handle`` for
  correlation instead. #4461
- Sessions awaiting a second factor can now access only MFA challenge and status
  routes and logout; other account, session, SSO identity, passkey, and
  re-authentication routes return ``401``. #4453

Documentation
-------------

- Added ``docs/authentication/customer-session-failure-matrix.md`` for session
  refusal behavior and troubleshooting. #4452
- Added ``docs/authentication/session-consistency-rollout.md`` for deployment
  and staging verification guidance. #4463
- Added ``docs/security/audits/security-audit-2026-09-19.md`` and updated the
  security risk register with the reviewed session-consistency risks. #4451,
  #4466
