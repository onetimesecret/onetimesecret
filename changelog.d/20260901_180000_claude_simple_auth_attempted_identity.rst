.. A new scriv changelog fragment.

Security
--------

- Simple-mode sign-in now validates the submitted password against the
  **account named in the login field only** — never against a customer the
  request's session already carried. Previously, a login submission arriving
  on a session-bearing request could re-authenticate as the session's own
  customer when the password matched *that* customer, silently ignoring the
  account the form named; the attempt was also never counted by the login
  rate limiter or the failed-sign-in audit. No privilege was escalatable (a
  password was always required for whoever got authenticated), and the path
  was unreachable through the stock controller, which turns already-signed-in
  submissions away — this hardens the authentication class itself. Full mode
  (Rodauth) always behaved this way; the two modes now agree, including the
  case where a signed-in user submits another account's correct credentials
  and the session switches to that account.

Fixed
-----

- The simple-mode ``Login failed`` log line now reports the account that was
  *attempted* (from the login field), not whichever customer the request's
  session carried — matching the attribution of the ``colonel.signin_failed``
  audit event fixed in #4361 and of full mode's login-failure log.
