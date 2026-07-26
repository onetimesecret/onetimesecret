.. A new scriv changelog fragment.

Changed
-------

- ``bin/ots domains repair``'s ``--force`` flag is now ``--yes`` (``-y`` /
  ``-f``), and the command defaults to a confirmation prompt.

- ``bin/ots domains repair`` now exits non-zero on failure paths that previously
  exited 0: domain not found, an orphaned domain invoked without ``--org-id``,
  and a stale organization reference. Runbooks that treated exit 0 as success
  will start failing on these — correctly, since nothing was repaired. Passing
  ``--org-id`` for a domain that is *not* orphaned is now a hard error pointing
  at ``domains transfer``; it was previously accepted and silently ignored.

- ``bin/ots domains probe --timeout`` now takes effect. dry-cli does not coerce
  ``type: :integer``, so the value arrived as a string and raised inside the
  HTTP timeout path — every non-default ``--timeout`` was broken. The value is
  now coerced and validated.
