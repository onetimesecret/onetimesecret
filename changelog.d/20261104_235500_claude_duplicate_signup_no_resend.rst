.. A new scriv changelog fragment.

Security
--------

- In full authentication mode, a sign-up for an address that already has an
  account now gets the same response as a new sign-up, instead of the 400
  "Unable to create account" error, so the response does not show whether the
  address is registered. The duplicate sign-up writes nothing and sends no
  email, whether or not the existing account is verified. The address owner
  can still request a new verification email with Resend.
