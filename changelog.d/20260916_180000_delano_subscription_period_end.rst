.. A new scriv changelog fragment.

Fixed
-----

- Fixed Colonel organization and billing views failing when a subscription
  period end was stored as a number. Existing string values remain supported,
  and missing or malformed values no longer render as 1 January 1970 or an
  invalid date.
