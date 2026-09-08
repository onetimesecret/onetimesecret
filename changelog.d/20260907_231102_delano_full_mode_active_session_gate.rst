Security
--------

- In ``full`` authentication mode, revoking an active session now ends it.
  A signed-in browser holds two records: the Rack session (the cookie-bound
  session stored in Redis) and an active-session row in Rodauth's
  ``account_active_session_keys`` table. Every authenticated request, on the
  API, the web controllers and the ``/auth`` surface alike, now checks that
  the Rack session's active-session row still exists. A row
  removed from the account's sessions page, by "sign out everywhere", or by
  an operator in Rodauth Admin causes the Rack session to be refused on its
  next request, instead of running until the cookie expired. Rack sessions
  signed in before this release carry no join key and are enforced from their
  next sign-in. The check fails closed: while the authentication database is
  unreachable, a Rack session whose row cannot be checked is refused with an
  error log rather than trusted unchecked. The Rack session itself is left in
  place and is honoured again once the database returns. A login whose join
  key cannot be stamped is refused rather than minting a session that no
  revocation could reach.
- The session deadlines configured for ``full`` mode are now enforced on
  every request: a session inactive for 24 hours, or older than 30 days,
  is signed out on its next request and its active-session row removed.
  Before this the deadlines were applied only when the account's sessions
  page was opened.
- Accepting an invitation now signs the new account in through the same
  path as a browser login, so the session it creates can be seen and revoked
  like any other. Previously it was invisible to the sessions page and to
  "sign out everywhere".
- A browser whose session was revoked can still present a credential on
  its first request: sign-up, password reset, magic link, passkey and SSO
  routes proceed as signed-out requests instead of answering 401 once. For
  SSO this matters, since the callback's authorization code is spent on the
  first attempt.
