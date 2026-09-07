.. A new scriv changelog fragment.

Fixed
-----

- Verified signups now retain a validated ``?redirect=`` destination across
  email confirmation, including when the confirmation link opens in another
  browser. A valid pending paid-plan selection still takes precedence (#4305).

- Paid-plan selections made before signup now reach the web-app checkout
  handoff instead of being consumed during email verification (#4305).

- Passkey sign-in now applies the same post-authentication destination rules as
  password sign-in: a valid pending plan selection, then a validated
  ``?redirect=`` destination (#4305).

Security
--------

- Redirect destinations now accept internal paths only, preventing malformed
  or external targets from crossing the authentication boundary (#4305).

- Authentication logs and diagnostic payloads no longer include redirect-borne
  invitation or email-confirmation credentials (#4305).

AI Assistance
-------------

- AI assistance was used to trace the redirect drop points across the
  signup, verification, and passwordless sign-in flows, implement the
  server-side persistence with parity validators, and build the
  end-to-end browser coverage.
