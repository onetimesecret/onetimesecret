.. A new scriv changelog fragment.

Fixed
-----

- Full authentication mode: completing the second factor now issues a new
  session id, as the password step already did. The old id is ended the way
  a logout ends it and the signed-in session, its active-session row and its
  per-value session keys carry across. A sign-in whose old id cannot be
  ended is refused and the user signs in again, so no half-authenticated
  session is ever left behind.

Changed
-------

- ``site.middleware.cookie_tossing`` (``MIDDLEWARE_COOKIE_TOSSING``) now
  defaults to on. A request that carries the session cookie more than once,
  as a cookie planted from a sibling or parent host would, is refused with
  ``403`` whichever cookie comes first; the response clears the session
  cookie for the request host and for every parent domain of it, so the one
  refused request removes both the planted cookie and the legitimate one and
  the next request starts a fresh session. The middleware is bound to the
  configured session cookie name and keeps no state between requests (the
  stock rack-protection class remembers a refused request for the life of
  the process). Set ``MIDDLEWARE_COOKIE_TOSSING=false`` to turn it off.
