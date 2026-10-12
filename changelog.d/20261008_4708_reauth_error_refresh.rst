Fixed
-----

- Re-authentication refuses a request with no surface before it renews the
  session id. When the proof cannot be saved after the renewal, the response
  is ``503 reauth_not_recorded`` with ``session_rotated: true``, and the app
  adopts the renewed session instead of reloading the page at its next
  refresh (#4708).
