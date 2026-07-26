.. A new scriv changelog fragment.

Fixed
-----

- An operator-initiated email change that could not reset the account's
  verified state no longer reports success. Previously the reset was
  best-effort: if it failed, the change still returned success and the account
  stayed marked verified on an address nobody had proven ownership of. The
  verified flag is now cleared directly (scoped to the account's own row, and
  only when that row is actually marked verified, so it can never revive a
  closed account), and if even that cannot be confirmed the change reports
  ``verification_not_reset`` — the CLI exits non-zero and names the remediation,
  and the colonel endpoint refuses to answer 200.

- The same reset is no longer skipped when the two stores disagree about
  verification. It previously short-circuited on the Redis mirror alone, so an
  account whose authoritative auth-database row still said "verified" was left
  untouched with no warning at all.

- In simple (Redis-only) mode, the email address is now claimed atomically
  before the customer record is re-keyed. Previously a concurrent signup or
  email change that claimed the same address in a narrow window had its index
  entry silently overwritten, leaving one of the two accounts unreachable by
  email. In full mode the auth database's unique constraint already served this
  purpose and continues to.
