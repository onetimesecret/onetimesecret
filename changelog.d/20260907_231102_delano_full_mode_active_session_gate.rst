Security
--------

- In ``full`` authentication mode, revoking a session now ends it. Every
  authenticated request checks that the session's row in Rodauth's active
  session table still exists; a row removed from the account's sessions page,
  by "sign out everywhere", or by an operator in Rodauth Admin refuses the
  session on its next request instead of letting it run until the cookie
  expired. Sessions signed in before this release carry no join key and are
  enforced from their next sign-in. The check fails closed: while the
  authentication database is unreachable, sessions are refused with an
  error log rather than trusted unverified.
