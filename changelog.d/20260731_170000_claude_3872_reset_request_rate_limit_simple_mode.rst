.. A new scriv changelog fragment.

Security
--------

- Extended the password-reset request rate limiter to simple authentication
  mode, the application default. The two-tier limiter added in #3872 was wired
  only into the Rodauth ``before_reset_password_request_route`` hook, which is
  loaded exclusively in full mode — so in a default install ``POST
  /auth/reset-password-request`` had no throughput cap at all, letting an
  unauthenticated caller mail-bomb arbitrary addresses and accumulate unbounded
  samples against the endpoint's accepted response-timing residual. The shared
  reset-request logic now enforces the same limiter itself, before the email
  format check and before any account lookup, using the same subjects as the
  full-mode hook: the trusted-proxy-resolved, privacy-masked client IP (tight
  tier) and the submitted address (higher backstop). Both tiers key only on
  request-observable inputs, so the 429 discloses nothing about account
  existence. Configuration is unchanged
  (``site.authentication.reset_request_rate_limit`` /
  ``RESET_REQUEST_RATE_LIMIT_*``, enabled by default) and now applies in both
  auth modes.
