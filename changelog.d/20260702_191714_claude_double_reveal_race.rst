.. A new scriv changelog fragment.

Security
--------

- Fixed a double-reveal race on burn-after-reading secrets (CWE-362). Two
  concurrent requests to the same secret link could both pass the viewability
  check, decrypt, and return the plaintext before either destroyed the record,
  so a "view once" secret could be disclosed to more than one recipient —
  defeating the core product promise. Revealing or burning a secret now claims
  it with an atomic compare-and-set in the datastore, so exactly one caller may
  consume it; any request that loses the race receives no secret value.

- Closed a related re-exposure window. Recording that a secret link had been
  viewed wrote the secret's state unconditionally, which could momentarily
  revert a just-revealed secret back to a viewable state while its ciphertext
  still existed, and could recreate a secret that a concurrent reveal or burn
  had already destroyed. The state transition is now atomic and can neither
  revert a consumed secret nor recreate a destroyed one.

Changed
-------

- Viewing a secret link no longer resets the secret's expiration. Previously
  each view extended the time-to-live back to the full lifespan, so a
  repeatedly-viewed link could outlive its intended expiry; secrets now always
  expire on their original schedule regardless of how often the link is viewed.
