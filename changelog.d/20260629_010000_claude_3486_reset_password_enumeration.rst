.. A new scriv changelog fragment.

Security
--------

- Password-reset requests no longer reveal whether an email address has an
  account (CWE-204). ``ResetPasswordRequest`` previously returned a generic
  success for a registered address but raised "Invalid email address" for an
  unregistered one, which allowed account enumeration. Validation now checks
  only the email format; a well-formed but unregistered address gets the same
  generic success response, with no reset secret created and no email sent —
  matching the existing ``CreateAccount`` behaviour. (#3486)
