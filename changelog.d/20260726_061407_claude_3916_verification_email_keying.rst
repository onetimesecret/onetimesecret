.. A new scriv changelog fragment.

Security
--------

- Re-keyed admin verification updates off bare email. In full authentication
  mode, ``SetCustomerVerification`` updated the Rodauth ``accounts`` row with
  ``WHERE email = ?``, but the unique index on ``accounts.email`` is partial
  (``status_id IN (1, 2)``), so a Closed account can share a live row's
  address. A plain ``bin/ots customers verify`` (or the colonel endpoint) would
  then silently resurrect a Closed account (status 3 → 2) when no live sibling
  existed, or die with an unhandled ``Sequel::UniqueConstraintViolation`` when
  one did — leaving that customer permanently un-verifiable through every admin
  surface. The update is now keyed on the ``external_id``-linked row (legacy
  rows without an ``external_id`` fall back to email restricted to live,
  unlinked rows), constrained to live statuses so a Closed row is never
  touched, and a new ``AccountClosed`` error is reported cleanly by the CLI and
  colonel surfaces instead of a stack trace. The self-service Rodauth
  ``after_verify_account`` path was never affected. (#3916)
