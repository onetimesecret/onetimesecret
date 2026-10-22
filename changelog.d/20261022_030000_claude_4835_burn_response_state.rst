.. A new scriv changelog fragment.

Fixed
-----

- ``POST /receipt/{id}/burn`` (v2 and v3) now returns the receipt as it
  is after the burn (``state: burned``, ``is_burned: true``) instead of
  the copy loaded before it. The secret link fields in that response now
  match a fresh fetch of the receipt, since the burned secret no longer
  has one. (#4835)
