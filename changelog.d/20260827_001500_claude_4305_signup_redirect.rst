.. A new scriv changelog fragment.

Fixed
-----

- The ``?redirect=`` return destination now survives the complete signup
  journey (#4305). Previously it worked for direct sign-in but was dropped
  after email verification: signup → check-email → verification link →
  sign-in always landed on the homepage. The validated destination is now
  stored server-side at signup (24-hour TTL) and replayed by the
  verify-account response, so it survives opening the verification link in
  a different browser, and the full internal path — query string and hash
  included — is preserved. A pending paid-plan selection still takes
  precedence over the redirect.

- Selecting a paid plan before signup works again for the web app. The
  plan intent was being consumed during email verification through a
  redirect mechanism JSON clients never receive, so the post-sign-in
  checkout hand-off found nothing (and the fallback destination pointed at
  a route that no longer exists).

- Magic-link and passkey sign-in now honor the same post-authentication
  destination rules as password sign-in (plan selection, then a validated
  ``?redirect=``) instead of always landing on the homepage.

Security
--------

- Redirect targets are validated with one hardened ruleset, enforced
  identically in the backend and the frontend: internal paths only, with
  protocol-relative (``//``), backslash, control-character,
  percent-encoded traversal, and scheme-smuggling forms rejected at every
  trust boundary.

AI Assistance
-------------

- AI assistance was used to trace the redirect drop points across the
  signup, verification, and passwordless sign-in flows, implement the
  server-side persistence with parity validators, and build the
  end-to-end browser coverage.
