.. A new scriv changelog fragment.

Security
--------

- Closed the account-enumeration oracle in the invite signup endpoint
  (``POST /api/invite/:token/signup``). It previously returned a distinct
  ``account_exists`` error when the invited email already had an account,
  re-opening the oracle the AZ7 hardening removed from the sibling
  show-invite endpoint — exploitable by any registered user who invites a
  target address and probes the token. The endpoint now validates the
  password before any account-existence check (an invalid-password probe
  gets a byte-identical error whether or not the account exists) and
  collapses all existing-account outcomes — authdb pre-check, Redis
  pre-check, and the Rodauth create race — into one generic
  ``signup_unavailable`` error whose conditional message never confirms
  account existence. The frontend keys its sign-in fallback off that
  error_type instead of sniffing the message text, so the invitee UX is
  unchanged. Residual: with a valid password, "exists" remains
  distinguishable from a successful signup — inherent to any signup
  endpoint, and probing it is destructive and noisy (creates the account,
  emails the invitee); the per-IP ``InviteTokenRateLimiter`` bounds it.
  (#3856)
