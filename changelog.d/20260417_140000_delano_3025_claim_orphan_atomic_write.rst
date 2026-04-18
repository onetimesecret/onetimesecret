.. A new scriv changelog fragment.

Fixed
-----

- ``Onetime::CustomDomain.claim_orphaned_domain`` no longer calls ``save`` inside a raw ``dbclient.multi`` block. Inside MULTI, Familia's unique-index guard issues HGETs that return ``QUEUED`` instead of real identifiers, making the guard blind — the method could raise a spurious ``RecordExistsError`` or silently bypass validation under concurrent orphan claims. The block now uses Familia 2.6.0's ``atomic_write``, which runs ``prepare_for_save`` (and therefore ``guard_unique_indexes!``) outside the transaction with real reads, then wraps the scalar HMSET, index updates, and collection mutations (``add_to_organization_domains``, ``owners``) in a single MULTI/EXEC. Independent of #3020 — same surface symptom, different root cause. (#3025)
