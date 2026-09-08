Security
--------

- In ``full`` authentication mode, revoking an active session now ends it.
  A signed-in browser holds two records: the Rack session (the cookie-bound
  session stored in Redis) and an active-session row in Rodauth's
  ``account_active_session_keys`` table. Every authenticated request now
  checks that the Rack session's active-session row still exists. A row
  removed from the account's sessions page, by "sign out everywhere", or by
  an operator in Rodauth Admin causes the Rack session to be refused on its
  next request, instead of running until the cookie expired. Rack sessions
  signed in before this release carry no join key and are enforced from their
  next sign-in. The check fails closed: while the authentication database is
  unreachable, a Rack session whose row cannot be checked is refused with an
  error log rather than trusted unchecked. The Rack session itself is left in
  place and is honoured again once the database returns.
