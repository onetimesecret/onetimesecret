.. A new scriv changelog fragment.

Added
-----

- Added organization unique-index diagnostics and safe repairs to
  ``bin/ots org doctor``. Use ``--repair`` for missing and stale entries;
  duplicate live values are reported for operator resolution.

Fixed
-----

- Organization-doctor output now redacts indexed email addresses.

AI Assistance
-------------

- Claude assisted with organization-index diagnostics, repair support, and
  coverage.
