.. A new scriv changelog fragment.

Changed
-------

- An ordinary duplicate sign-up logs ``registration_blocked_existing_account``
  at info. ``registration_blocked_auth_db_conflict`` (error) is now logged only
  when the auth database has the account and the datastore has no customer
  record for it, which is what its hint always described. Alerts on that
  event will fire far less often.

Fixed
-----

- A sign-up that loses a race for its email address answers exactly like an
  ordinary duplicate sign-up, on SQLite and PostgreSQL; it used to answer
  ``422`` with "already an account with this login". A sign-up for an existing
  *unverified* account now answers ``400`` like one for a verified account; it
  answered ``403``, which told a caller the account's state.
