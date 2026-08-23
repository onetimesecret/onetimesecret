.. A new scriv changelog fragment.

Security
--------

- Passphrase verification on the v2 secret show, reveal, and burn endpoints
  now runs only when ``continue=true``. A metadata-only request
  (``continue`` absent or ``false``) no longer evaluates the supplied
  passphrase, so it cannot be used to test guesses without consuming the
  secret, and it no longer records or clears rate-limit state.
  ``details.correct_passphrase`` has been removed from the v2 secret
  responses; clients should use ``details.show_secret``, which is true only
  when the passphrase was correct and the reveal was committed. The v2
  reveal and burn endpoints now return the same status for a right or wrong
  passphrase when ``continue=false``. The v1 logic classes carry the same
  change for parity; the v1 API was not exposed, since its controller
  always commits (``continue=true``) and never returned the verdict.
