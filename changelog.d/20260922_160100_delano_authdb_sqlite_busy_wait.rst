.. A new scriv changelog fragment.

Fixed
-----

- Concurrent sign-ups against a SQLite auth database no longer answer ``500``
  (``database is locked``). Writers now take the write lock up front and wait
  for each other without holding the interpreter lock, so the waiting
  connection can actually be released. Migration connections, including
  ``rake auth:migrate``, use the same SQLite settings as request connections.
- ``ots status``, the migration connection and ``rake auth:migrate`` accept a
  multi-host PostgreSQL auth database URL (``host1:5432,host2:5432``), as
  request connections already did. ``ots status`` reported such a database as
  an error.
- ``/auth`` answers ``503`` with ``Retry-After: 1`` (``error_type:
  AuthDatabaseBusy``) when the auth database is saturated: a SQLite write lock
  held past the 5-second wait, or no free pooled connection on either engine.
  It answered a generic ``500``. Seeing it means more concurrent auth writes
  than the deployment has capacity for. The retryable ``503`` answers are
  logged at ``warn`` as ``Auth router translated exception`` with
  ``error_type`` and ``status``; ``Auth router unhandled exception``
  (``error``) now means only an exception ``/auth`` has no answer for.
