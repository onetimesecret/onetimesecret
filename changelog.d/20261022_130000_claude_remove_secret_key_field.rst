.. A new scriv changelog fragment.

Removed
-------

- The deprecated ``secret_key`` field on ``Receipt`` and ``Secret``, the
  pre-v0.24 name of ``secret_identifier``. No code has written a value to
  it since the rename (2025-11-03, first shipped in v0.24.0), ``expired!``
  no longer writes an empty string to it, and nothing reads it. A stale
  ``secret_key`` field in a receipt hash written before the rename is
  ignored on load and expires with the receipt; no migration is needed.
  On an install that skipped the v0.24.5 upgrade pipeline, ``expired!``
  used to blank that stale field when the secret expired; it now stays in
  the hash, unread, until the receipt key expires (twice the secret's
  lifespan).
  The ``secret_key`` name in v1 API responses is unaffected: it is built
  from ``secret_identifier``. (#4835)
