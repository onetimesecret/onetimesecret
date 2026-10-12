.. A new scriv changelog fragment.

Security
--------

- ``POST /auth/email-login-request`` is now rate limited per client IP and
  per submitted address before any account lookup, so one source can no
  longer mail sign-in links to address after address. It uses the same two
  tiers as the password-reset request limiter, under separate keys, and is
  on by default. The settings live under
  ``site.authentication.email_login_request_rate_limit``
  (``EMAIL_LOGIN_REQUEST_RATE_LIMIT_ENABLED``, ``_MAX_PER_IP`` (30),
  ``_MAX_PER_EMAIL`` (30), ``_WINDOW`` (3600), ``_LOCKOUT`` (3600)).
  ``bin/ots ratelimit`` and the colonel rate-limit reset accept the kinds
  ``email_login_request_ip`` and ``email_login_request_email``.
  ``POST /auth/verify-account-resend`` still has no per-source limit.
  (RISK-2026-08-14-M04)
