.. A new scriv changelog fragment.

AI Assistance
-------------

- Simple-mode reset-request rate limiting implemented end-to-end with Claude
  Code: the limiter call site, the integration and unit coverage, and the
  operator/audit documentation. The specs were then hardened against an
  adversarial review pass that found two of them passing under mutation, and
  that pass also surfaced the invalid-UTF-8 constructor path that bypassed the
  new counter.
