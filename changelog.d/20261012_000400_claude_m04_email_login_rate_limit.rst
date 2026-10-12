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
  ``_MAX_PER_EMAIL`` (90), ``_WINDOW`` (3600), ``_LOCKOUT`` (3600)). The
  per-address cap is kept above the per-IP cap so that one source cannot lock
  another person out of magic-link sign-in. ``bin/ots ratelimit`` and the
  colonel rate-limit reset accept the kinds ``email_login_request_ip`` and
  ``email_login_request_email``. ``POST /auth/verify-account-resend`` still
  has no per-source limit. (RISK-2026-08-14-M04)

  **Upgrade note for installs behind a reverse proxy with magic links
  enabled**: the per-IP tier counts the resolved client IP. With
  ``TRUSTED_PROXY_ENABLED`` unset (the default) that is the proxy's own
  address, so every visitor shares one bucket and magic-link requests return
  429 for everyone for an hour after 30 requests in an hour. Set
  ``TRUSTED_PROXY_ENABLED=true`` before upgrading, or raise
  ``EMAIL_LOGIN_REQUEST_RATE_LIMIT_MAX_PER_IP``, or opt out with
  ``EMAIL_LOGIN_REQUEST_RATE_LIMIT_ENABLED=false``.
