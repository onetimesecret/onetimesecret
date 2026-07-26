.. A new scriv changelog fragment.

Added
-----

- ``bin/ots customers change-email`` changes an account's email address across
  both stores, backed by ``Auth::Operations::Customers::ChangeEmail``, with
  optional ``--reason`` / ``--ticket`` recorded in the audit detail. A matching
  colonel endpoint (``POST /users/:user_id/email``) is available for support.

- ``customers doctor`` gained three checks: ``auth_email_drift`` (the Rodauth
  account address and the Redis customer address disagree),
  ``org_email_index_stale`` and ``org_contact_email_stale``. The first is what
  makes a partially-applied email change detectable — the previous checks only
  compared Redis against Redis.

Changed
-------

- Confirming a self-service email change no longer sweeps sessions by scanning
  the keyspace. It delegates to the same index-based revocation operation used
  elsewhere. The old scan-first approach could exhaust its scan budget before
  reaching the target account's sessions and still report success, which at
  production account volumes meant sessions could survive an email change.
