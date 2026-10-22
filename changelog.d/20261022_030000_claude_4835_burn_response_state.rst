.. A new scriv changelog fragment.

Changed
-------

- Receipts whose secret is gone (revealed, burned, expired, orphaned) now
  return ``share_path``/``share_url`` as ``null`` and omit
  ``secret_identifier`` from both the receipt and burn responses, instead
  of a dangling ``secret/`` link. (#4835)

Fixed
-----

- ``POST /receipt/{id}/burn`` (v2 and v3) now returns the receipt as it
  is after the burn (``state: burned``, ``is_burned: true``) instead of
  the copy loaded before it. (#4835)

Security
--------

- The burn endpoint now applies the same share-link gate as the receipt
  page. A burn request that does not commit (``continue=false``) on a
  guest-submitted (incoming) secret no longer returns the share link that
  the receipt page withholds from its creator. (#4835)
