.. A new scriv changelog fragment.

Changed
-------

- Closing an account in full authentication mode now deletes the Rodauth
  ``accounts`` row and every ``account_authentication_audit_logs`` row for
  it, in the same transaction as the closure, on PostgreSQL and SQLite.
  Before this release the row was kept with status Closed, together with
  the account's plaintext email and its complete sign-in history (client IP,
  user agent and correlation id per event), with no expiry. Administrative
  purges (``bin/ots customers purge``, ``purge-inactive``, the Colonel
  endpoint) and the simple-mode delete endpoint delete the same rows.
  Signing up again with the address still creates a new, empty account.
  (#4819)

Added
-----

- ``bin/ots customers prune-closed-accounts`` deletes the closed rows and
  audit logs that closures before this release left behind. It previews by
  default; add ``--confirm`` to delete. Run it once after upgrading. (#4819)
