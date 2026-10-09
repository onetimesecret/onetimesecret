.. A new scriv changelog fragment.

Changed
-------

- Password sign-in in simple authentication mode now starts a new session
  id, as full mode already does. The session the browser held before
  signing in is ended the way a sign-out ends it, and nothing in it is
  carried into the signed-in session; the sign-in response includes a new
  CSRF token. If the old session cannot be ended, sign-in does not
  complete: JSON clients get a 503 and the sign-in form shows a message
  asking to try again (#4466).
