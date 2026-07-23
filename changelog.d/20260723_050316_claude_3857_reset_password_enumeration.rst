.. A new scriv changelog fragment.

Security
--------

- Closed an account-enumeration oracle on the password-reset request endpoint.
  In full authentication mode the Rodauth-backed
  ``POST /auth/reset-password-request`` answered a request for a registered
  address differently from an unregistered one — and differently again for an
  unverified account or one that was emailed moments earlier — letting an
  unauthenticated caller probe which email addresses have accounts (CWE-204).
  The endpoint now returns the same generic "an email has been sent" response in
  every case, matching the enumeration-safe behavior the basic-mode endpoint
  already enforced, while still sending a reset email only for a valid, verified
  account and preserving Rodauth's resend throttle. (#3857)
