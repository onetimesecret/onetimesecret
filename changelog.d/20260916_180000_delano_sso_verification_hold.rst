.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots customers doctor --repair`` now preserves SSO customers that were
  deliberately left unverified and reports them for manual verification.
  Follow-up to #3973.

Security
--------

- SSO customers remain unverified when their provider explicitly rejects email
  verification or the ``email_verified`` claim cannot be read.

Documentation
-------------

- Added ``docs/runbooks/sso-accounts-unverified.md`` for detecting and repairing
  unverified SSO customer records after an upgrade, including records affected
  before #3973 and the related role-index reconciliation in #3974.
