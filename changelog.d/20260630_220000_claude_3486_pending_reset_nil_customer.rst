.. A new scriv changelog fragment.

Fixed
-----

- A password-reset request for a pending (unverified) account no longer returns
  a 500. ``send_verification_email`` bound the verification secret to the
  request-context customer, which is nil in the unauthenticated reset flow; it
  now accepts the recipient explicitly (defaulting to ``cust``), so the resend
  succeeds and the request returns the same generic success as every other case
  — keeping the password-reset response uniform across registered, pending and
  unregistered addresses. (#3486)
