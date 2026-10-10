.. A new scriv changelog fragment.

Fixed
-----

- Accounts that signed in through SSO before this release could keep the
  identity provider's capitalisation of their email address in the
  authentication database, which made new-login alerts, MFA, active-session
  listing and account teardown unable to find the matching customer
  record. The new ``bin/ots customers normalize-emails`` command previews
  (by default) and, with ``--confirm``, rewrites those addresses to the
  lowercase form every other sign-up path stores, without signing anyone
  out, resetting verification or sending mail. Rows whose lowercase form
  would collide with another account, or whose address lowercasing cannot
  represent faithfully, are reported and left for the operator (#4726).
- ``bin/ots customers doctor`` now reports an authentication-database email
  that matches its customer record only case-insensitively as
  ``auth_email_not_canonical``, pointing at ``customers normalize-emails``,
  so the rows that command would rewrite are visible before the run and
  confirmed gone after it (#4726).
