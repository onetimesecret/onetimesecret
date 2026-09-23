.. A new scriv changelog fragment.

Fixed
-----

- Concurrent sign-ups using SQLite no longer fail with ``database is locked``.
  Migration and request connections now use the same SQLite settings.
- ``ots status`` and auth database migrations now accept multi-host PostgreSQL
  URLs.
- ``/auth`` now returns retryable ``503`` responses when the auth database is
  busy or its connection pool is exhausted, instead of a generic ``500``.
