.. A new scriv changelog fragment.

Security
--------

- The recent-secrets list kept in the browser tab for guests no longer stores
  the secret link itself, only what is needed to list and reopen receipts.
  Expired entries are dropped, and nothing is stored for signed-in users,
  whose list comes from their account. Entries saved by earlier versions are
  rewritten without the link the first time they load. After a page reload,
  a guest copies the secret link from the receipt page instead of the list.
  (RISK-2026-08-14-M10)
