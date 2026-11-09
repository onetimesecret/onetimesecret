.. A new scriv changelog fragment.

Fixed
-----

- Secret creation commits the encrypted secret, its receipt and the
  registrations that make them discoverable in one datastore transaction.
  A failure anywhere in that commit answers with an error; the caller never
  receives a handle to a partial pair (#4873, #4867).
- Receipt updates after a reveal or burn are written conditionally and
  atomically, and cleanup of the consumed secret is attempted after
  consumption instead of being left to the next read (#4867). When that
  cleanup itself fails, the secret's ciphertext is still removed from the
  stored record before the error is returned, instead of remaining until the
  record expires.
- Incoming secrets (``/api/incoming``) persist their trusted metadata on the
  receipt's first save (#4869).
- Malformed request input, such as unparseable parameters or a form ``POST``
  without a content type, is answered as a client error before dispatch
  instead of a server error (#4866).

Changed
-------

- ``OPTIONS /secret/generate`` and ``OPTIONS /secret/conceal`` on the v2 and
  v3 APIs answer ``204`` without running creation logic, counting against
  quotas or granting CORS. ``HEAD`` on the one-time read routes (v2 and v3
  ``secret`` and ``receipt`` show, guest routes included) answers ``405`` with
  an ``Allow`` header instead of consuming the secret; ``GET`` is unchanged
  (#4866).
- The v3 OpenAPI document matches what the API accepts and returns:
  ``continue`` on reveal and burn is a boolean or a string, ``passphrase`` is
  documented on burn, ``memo`` on ``PATCH /receipt/:identifier``, and
  ``GET /receipt/recent`` takes ``scope`` and ``domain_extid`` as query
  parameters, refusing a structured ``scope`` with ``422`` (#4868, #4870).
- Rotating an API key (``POST /api/account/apitoken``, ``bin/ots apitoken``)
  now retires every v3 bearer token issued before the rotation, without
  signing the browser session out. Bearer tokens are off by default; see the
  PASETO entry in this release.

AI Assistance
-------------

- The request-handling hardening, receipt persistence changes, contract
  alignment and their tests were written with AI assistance.
