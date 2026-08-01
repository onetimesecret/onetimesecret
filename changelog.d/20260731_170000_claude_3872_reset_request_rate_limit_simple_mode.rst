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

  **Upgrade note for simple-mode operators.** Because the limiter is enabled by
  default, an install that has never set
  ``site.authentication.reset_request_rate_limit`` starts throttling this
  endpoint after upgrading — previously only full-mode installs did. The per-IP
  bucket is the privacy-MASKED client network (/24 for IPv4, /48 for IPv6 — the
  raw address never survives the IP-privacy middleware, the same granularity as
  every other IP-keyed limiter here), so users sharing one NAT egress share one
  budget: 10 reset requests per hour by default, then a one-hour lockout for
  that network. Sites with dense NAT populations should raise
  ``RESET_REQUEST_RATE_LIMIT_MAX_PER_IP`` (or shorten
  ``RESET_REQUEST_RATE_LIMIT_LOCKOUT``); ``RESET_REQUEST_RATE_LIMIT_ENABLED=false``
  opts out entirely. The per-address backstop is unaffected by IP granularity.

  **Configure trusted-proxy resolution if you run behind a reverse proxy.**
  ``TRUSTED_PROXY_ENABLED`` ships as ``false``, and while it is off every
  forwarded header is ignored and ``REMOTE_ADDR`` is used directly — which
  behind nginx/Caddy/Traefik/an ingress is the *proxy's* address for every
  request. The per-IP tier then resolves to one bucket for the whole
  deployment, so 10 reset requests per hour from any users combined trip a
  site-wide lockout (and one caller can burn it deliberately). This is a
  property of every IP-keyed control here, not of this endpoint specifically,
  but the reset-request tier is keyed on IP alone, so it is the most exposed.
  Proxied deployments should set ``TRUSTED_PROXY_ENABLED=true`` with the
  matching ``TRUSTED_PROXY_MODE``/``TRUSTED_PROXY_CIDRS`` for their topology —
  after confirming the proxy overwrites client-supplied ``X-Forwarded-For``,
  since trusting that header from an untrusted hop makes the tier spoofable.
  Where that is not possible, raise the per-IP cap and rely on the per-address
  backstop, which is unaffected.
