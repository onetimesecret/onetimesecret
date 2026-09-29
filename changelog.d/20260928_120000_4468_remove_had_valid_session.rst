.. A new scriv changelog fragment.

Removed
-------

- The bootstrap field ``had_valid_session``, deprecated in 0.26.13, is no
  longer sent by ``GET /bootstrap/me`` or in page hydration. Read
  ``auth_status`` instead: the error-recovery case the field described is
  ``auth_status: "unavailable"``. A client from 0.26.13 ignores the missing
  key. (#4468)
