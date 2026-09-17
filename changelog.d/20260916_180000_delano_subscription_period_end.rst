.. A new scriv changelog fragment.

Fixed
-----

- Fixed the Colonel organization list, detail, investigate and user-billing
  views rejecting an organization whose subscription period end was stored
  as a number. Period ends are now written as integer epoch seconds; existing
  string records remain readable. The workspace billing overview no longer
  renders 1 January 1970 or an invalid date when the period end is missing or
  malformed.
