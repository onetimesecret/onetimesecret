.. A new scriv changelog fragment.

Security
--------

- In full authentication mode, a sign-up for an address that already has an
  account now gets the same response as a new sign-up, instead of the generic
  400 "Unable to create account" error, so the response does not show whether
  the address is registered. No account is written and no email is sent,
  whether or not the existing account is verified: a sign-up attempt does not
  mail the verification link of an account whose password the requester did
  not set. The address owner can request a new verification email with
  Resend, as before.
