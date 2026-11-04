.. A new scriv changelog fragment.

Fixed
-----

- A customer record recreated at login (a Rodauth account with no matching
  Customer in Redis) is now provisioned through the same operation the SSO
  JIT hook uses, with a ``verified_by`` derived from persisted auth state
  (``sso`` for accounts with an SSO identity, ``legacy`` when account
  verification is enabled, otherwise ``autoverify``), a ``login_recovery``
  provisioning origin, and a WARN log line. If that derivation fails the
  record is created unverified. Previously it was verified from a bare
  status check with no provenance. Follow-up to #3973.
  None of these counts as mailbox proof, so a recovered customer cannot
  use a system role until an operator verifies the address.

Security
--------

- ``verified_by`` provenance tags are now validated against a single list on
  the Customer model (``Onetime::Customer::VERIFIED_BY_VALUES``). Setting or
  provisioning a verified customer with an unknown tag raises before any
  write.

Documentation
-------------

- The SSO-accounts-unverified runbook now explains that records carrying a
  ``verification_hold`` are reported by the customers doctor but never
  auto-repaired.
