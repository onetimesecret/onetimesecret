.. A new scriv changelog fragment.

Changed
-------

- Re-authentication (POST /auth/reauth) now moves the session to a new
  session id before it records the proof that allows one SSO Connect. If
  the old session cannot be ended, no proof is recorded and the page asks
  to try again (#4466).
- Setting up the first second factor (an authenticator app or a passkey)
  on a session now moves it to a new session id. If the old session cannot
  be ended, the setup is not saved and the user stays signed in as before.
  Adding a further factor to a session that already completed two-factor
  sign-in keeps its id. The app picks up the new session after either
  change without a page reload (#4466).
