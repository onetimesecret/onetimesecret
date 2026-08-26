.. A new scriv changelog fragment.

Fixed
-----

- The API Key settings page no longer breaks for accounts promoted to
  ``admin`` or ``staff`` via ``bin/ots customers role`` (#4298). The
  frontend role enum now mirrors the backend's assignable roles (enforced
  by a contract test against ``SetRole::VALID_ROLES``), and an unknown or
  missing ``role`` degrades to ``customer`` instead of failing the whole
  account record parse.

Changed
-------

- Frontend Sentry events now serialize nested extras to depth 6
  (``normalizeDepth``), so schema-validation failures report their
  ``issues[]`` payload instead of ``"[Array]"``.

AI Assistance
-------------

- AI assistance was used to trace the Sentry signatures to the role
  vocabulary mismatch, sync the enums, and add the drift-guard contract
  test.
