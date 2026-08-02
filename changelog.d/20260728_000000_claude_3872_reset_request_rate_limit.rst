.. A new scriv changelog fragment.

Security
--------

- Added rate limiting to the password-reset request endpoint. In full
  authentication mode ``POST /auth/reset-password-request`` was made
  enumeration-safe earlier (#3857) but retained an accepted response-timing
  residual; exploiting it statistically requires many requests per target
  address. The route now enforces a two-tier limiter before any account lookup
  runs: a tight per-client-IP cap (default 10 requests/hour, using the
  trusted-proxy-resolved, privacy-masked client IP so forwarded headers cannot
  spoof it) and a higher per-submitted-address backstop (default 30/hour,
  case-normalized) that bounds IP-rotating callers probing a single target.
  Both tiers key only on request-observable inputs — never on whether the
  address maps to an account — so the 429 response discloses nothing about
  account existence. This stacks with Rodauth's per-account resend throttle,
  which caps emails but not request volume per source. Configurable via
  ``site.authentication.reset_request_rate_limit`` /
  ``RESET_REQUEST_RATE_LIMIT_*``; enabled by default. (#3872)
