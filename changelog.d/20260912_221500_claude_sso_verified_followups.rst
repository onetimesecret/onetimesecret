.. A new scriv changelog fragment.

Fixed
-----

- A customer record recreated at login (a Rodauth account with no matching
  Customer in Redis) is now provisioned through the same operation the SSO
  JIT hook uses, with a truthful ``verified_by`` derived from persisted auth
  state (``sso`` for accounts holding an SSO identity, ``email`` when account
  verification is enabled, otherwise ``autoverify``), a ``login_recovery``
  provisioning origin, and a WARN log line. If that derivation fails the
  record is created unverified. Previously it was verified from a bare
  status check with no provenance. Follow-up to #3973.

- ``bin/ots customers doctor --repair`` no longer re-verifies an SSO
  customer whose identity provider explicitly asserted ``email_verified:
  false`` at sign-in. The JIT hook now records that veto on the customer
  (``sso_email_unverified``); the doctor reports such records for manual
  verification instead of treating them as drift.

Security
--------

- The OmniAuth ``email_verified`` claim reader now fails closed: if an auth
  hash raises while the claim is read, the SSO customer is created unverified
  and a warning is logged, instead of the veto being silently dropped.

- ``verified_by`` provenance tags are now validated against a single list on
  the Customer model (``Onetime::Customer::VERIFIED_BY_VALUES``). Setting or
  provisioning a verified customer with an unknown tag raises before any
  write.

Documentation
-------------

- New runbook ``docs/runbooks/sso-accounts-unverified.md`` for operators
  upgrading past 0.26.5: how to detect and repair SSO customers left
  unverified before #3973 was fixed, and the sibling role-index reconcile
  (#3974).
