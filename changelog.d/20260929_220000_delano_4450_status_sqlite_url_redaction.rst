.. A new scriv changelog fragment.

Security
--------

- ``bin/ots status`` now masks the query string of a SQLite
  ``AUTH_DATABASE_URL`` as it already did for other adapters, so a value
  such as ``sqlite://data/auth.db?password=...`` is no longer printed in
  full. A SQLite URL without a query string is shown unchanged. (#4450)

Fixed
-----

- URL redaction in logs, the boot banner, the health endpoint and
  ``bin/ots status`` no longer treats a ``:`` or ``@`` in a SQLite file path
  as credentials. The path is shown whole and only the query string is
  masked; the boot banner now shows ``sqlite::memory:`` instead of
  ``****``. (#4450)
