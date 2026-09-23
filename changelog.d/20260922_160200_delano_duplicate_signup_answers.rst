.. A new scriv changelog fragment.

Changed
-------

- Ordinary duplicate sign-ups now log
  ``registration_blocked_existing_account`` at info; alerts on
  ``registration_blocked_auth_db_conflict`` now indicate an auth database and
  customer datastore mismatch.

Fixed
-----

- Concurrent and ordinary duplicate sign-ups now return the same response on
  SQLite and PostgreSQL. Responses no longer disclose whether an existing
  account is verified.
