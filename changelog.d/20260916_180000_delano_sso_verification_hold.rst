.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots customers doctor --repair`` no longer re-verifies an SSO customer
  that the JIT hook deliberately left unverified. The hook now records why on
  the customer (``verification_hold``: ``idp_unverified`` when the identity
  provider asserted ``email_verified: false``, ``claim_unreadable`` when that
  claim could not be read), and the doctor reports such records for manual
  verification instead of treating them as drift. Follow-up to #3973.

Security
--------

- The OmniAuth ``email_verified`` claim reader now fails closed: if an auth
  hash raises while the claim is read, the SSO customer is created unverified
  with a ``claim_unreadable`` hold and a warning is logged, instead of the
  error being swallowed and the customer minted as verified.

Documentation
-------------

- New runbook ``docs/runbooks/sso-accounts-unverified.md`` for operators
  upgrading past 0.26.5: how to detect and repair SSO customers left
  unverified before #3973 was fixed, what a ``verification_hold`` means, and
  the sibling role-index reconcile (#3974).
