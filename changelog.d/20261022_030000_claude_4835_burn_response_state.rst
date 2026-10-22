.. A new scriv changelog fragment.

Changed
-------

- Receipts whose secret is gone (revealed, burned, expired, orphaned) now
  return ``share_path``/``share_url`` as ``null`` and omit
  ``secret_identifier`` from both the receipt and burn responses, instead
  of a dangling ``secret/`` link. (#4835)

- A burn whose receipt expires or is deleted while the burn runs now
  returns 404, as a follow-up fetch would, instead of the receipt's
  pre-burn state. The secret is still destroyed. (#4835)

- v1 ``GET /receipt/{id}`` no longer writes the deprecated ``secret_key``
  receipt field, and v1 responses no longer read it. A key found only in
  that field named a secret the receipt cannot load. (#4835)

Fixed
-----

- ``POST /receipt/{id}/burn`` (v1, v2 and v3, including the ``/private``
  and ``/metadata`` aliases) now returns the receipt as it is after the
  burn (``state: burned``) instead of the copy loaded before it. In v1 the
  ``state.secret_key`` field is now empty after a burn. (#4835)

- v1 ``GET /receipt/{id}`` returned ``metadata_url`` and ``receipt_url``
  ending in ``/receipt/`` because they were built from a deprecated field
  that is no longer written. They now end in the receipt identifier.
  (#4835)

- v1 no longer returns a secret key for a revealed, burned, expired or
  orphaned receipt that still has a value in the deprecated ``secret_key``
  field. (#4835)

- A burn request that does not commit (``continue=false``) now includes
  ``secret_identifier`` under the same rule as ``GET /receipt/{id}``: only
  while the secret has no passphrase and the receipt has not been
  previewed. The two responses disagreed for passphrase-protected secrets
  and previewed receipts. ``share_url`` is unchanged. (#4835)

Security
--------

- The burn endpoint now applies the same share-link gate as the receipt
  page. A burn request that does not commit (``continue=false``) on a
  guest-submitted (incoming) secret no longer returns the share link that
  the receipt page withholds from its creator. (#4835)

- v1 ``GET /receipt/{id}`` (and its ``/private`` and ``/metadata`` aliases)
  returned the secret key of a guest-submitted (incoming) secret to anyone
  holding the receipt identifier, including the guest who submitted it.
  v1 now withholds it, as v2 and v3 already did. (#4835)
