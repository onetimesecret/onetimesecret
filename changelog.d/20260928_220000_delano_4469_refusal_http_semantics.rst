.. A new scriv changelog fragment.

Changed
-------

- A protected API or ``/auth`` request whose session could not be verified
  (datastore or auth database unreachable) now answers ``503`` with
  ``Retry-After: 5`` instead of ``401``. The body is unchanged and still
  carries ``code_scope: verification_unavailable``; the session is kept. Every
  coded ``401`` now carries a ``WWW-Authenticate`` challenge:
  ``Session realm="onetimesecret"`` for a session or form credential,
  ``Basic realm="onetimesecret"`` for a rejected ``Authorization`` header.
  Update alerts that counted the outage as a ``401``, and confirm that an
  intermediary in front of the API passes origin ``503`` bodies through. See
  ``docs/authentication/session-consistency-rollout.md``. (#4469)
