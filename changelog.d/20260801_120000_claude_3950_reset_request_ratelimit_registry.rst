.. A new scriv changelog fragment.

Added
-----

- The reset-password-request rate limiter is now registered with the operator
  rate-limit tooling as two kinds, ``reset_request_ip`` and
  ``reset_request_email``. Both are now reachable from the two supported
  operator paths, which previously offered no way to clear a reset-request
  lockout — an operator whose deployment tripped the per-IP tier had to wait it
  out. ``bin/ots ratelimit keys <kind> <subject>`` EMITS the ``TTL``/``GET``/
  ``DEL`` command text for the pair without touching the datastore itself, so it
  clears a lockout only once piped (``| grep -v '^#' | valkey-cli``); the
  colonel ``GET /api/colonel/ratelimit/inspect`` and ``POST
  /api/colonel/ratelimit/reset`` endpoints read and delete those same keys
  directly, and the reset records an admin audit event. Subjects
  are the STORED form: the privacy-masked client IP (/24 IPv4, /48 IPv6) for the
  IP tier and the normalized address (strip + NFC + case-fold) for the backstop;
  a raw address or mixed-case login reads back as not set. Enforcement,
  key shapes and limiter defaults are unchanged.

- A password-reset IP-tier lockout now logs an operator hint when
  ``site.network.trusted_proxy`` is not enabled, naming the remedy
  (``TRUSTED_PROXY_ENABLED=true``, or a higher
  ``RESET_REQUEST_RATE_LIMIT_MAX_PER_IP``). In that configuration the resolved
  client IP is ``REMOTE_ADDR`` — the proxy's own address behind a reverse proxy —
  so every visitor shares one bucket and the lockout is deployment-wide rather
  than per-origin. The hint is a server log line only; it never appears in a
  response and does not vary on whether an account exists.
