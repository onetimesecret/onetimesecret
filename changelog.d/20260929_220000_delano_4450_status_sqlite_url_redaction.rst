.. A new scriv changelog fragment.

Security
--------

- ``bin/ots status`` now masks the query string of a SQLite
  ``AUTH_DATABASE_URL`` as it already did for other adapters, so a value
  such as ``sqlite://data/auth.db?password=...`` is no longer printed in
  full. A SQLite URL without a query string is shown unchanged. (#4450)
