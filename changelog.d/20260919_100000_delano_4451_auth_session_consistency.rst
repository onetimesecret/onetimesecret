.. A new scriv changelog fragment.

Added
-----

- JSON ``401`` responses for refused sessions now include stable ``code`` and
  ``code_scope`` fields. #4462
- Clients can mark timer-driven ``GET`` and ``HEAD`` requests with
  ``X-Session-Activity: passive`` so they do not extend the inactivity deadline.
  #4455

Changed
-------

- Idle dashboard tabs now sign out at the configured inactivity deadline;
  background refreshes and refused requests no longer keep sessions active.
  #4455
- Tabs reload once and show a message when a session ends, is revoked, or is
  replaced elsewhere. Unsaved secrets receive a navigation warning. #4464, #4465
- Session logs now use ``session_handle`` instead of ``session_id`` and omit
  ``redis_key``. Update affected log queries, alerts, and dashboards. #4461
- Authentication and otherwise uncached API responses now send
  ``Cache-Control: private, no-store``. #4461, #4470
- Deploy this release's backend and frontend together. Mixed versions can
  temporarily degrade session handling. See
  ``docs/authentication/session-consistency-rollout.md``. #4463

Deprecated
----------

- The bootstrap field ``had_valid_session`` is deprecated and scheduled for
  removal in #4468.

Fixed
-----

- Logout and session revocation now prevent in-flight requests from restoring
  an ended session or its cookie.
- Repeated session-verification failures no longer sign the user out.
- Colonel now reports ``allowed_signup_domains`` validation errors against the
  correct field.

Security
--------

- Raw session IDs have been removed from logs because they could be replayed as
  session cookies. Use ``session_handle`` for correlation instead. #4461
- Sessions awaiting a second factor can access only MFA challenge and status
  routes and logout; other protected routes return ``401``. #4453

Documentation
-------------

- Added ``docs/authentication/customer-session-failure-matrix.md`` for session
  refusal behavior and troubleshooting. #4452
- Added ``docs/authentication/session-consistency-rollout.md`` for deployment
  and staging guidance. #4463
