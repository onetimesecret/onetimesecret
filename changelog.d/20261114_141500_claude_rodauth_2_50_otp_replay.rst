.. A new scriv changelog fragment.

Security
--------

- Upgraded rodauth to 2.50.0, which fixes GHSA-26qw-xq5q-hv9w. With MFA on
  (``AUTH_MFA_ENABLED=true``), the server accepts the authenticator code for
  the 30-second time step before and after its own, to allow for clock drift.
  A code for the later time step was accepted a second time 30 seconds after
  it had been used, while it was still inside that allowance. The advisory
  describes what a replay takes: the account's password and an already used
  code from an authenticator whose clock was ahead of the server's. The time
  step of an accepted code is now recorded, and that code is refused from
  then on, at setup, at sign-in and at re-authentication. No configuration
  change and no auth database migration.

Changed
-------

- The rodauth upgrade also changes two things outside MFA. Signing out now
  writes one ``logout`` row to the auth audit log; before, a second
  identical row could be written when the account had been loaded during the
  request. A requested path that starts with ``/\`` is no longer saved as
  the place to return to after sign-in.
