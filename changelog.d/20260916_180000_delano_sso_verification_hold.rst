.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots customers doctor --repair`` now preserves deliberately unverified
  SSO customers and reports them for manual verification. #3973

Security
--------

- SSO customers remain unverified when their provider rejects email verification
  or the ``email_verified`` claim cannot be read.

Documentation
-------------

- Added ``docs/runbooks/sso-accounts-unverified.md`` for detecting and repairing
  unverified SSO customer records after an upgrade.
