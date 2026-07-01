.. A new scriv changelog fragment.

Removed
-------

- The legacy v1 API is now strictly JSON-only. Its hand-rolled
  Content-Security-Policy, the per-request nonce it generated, and its unused
  HTML-response capability (the ``publically`` wrapper and ``carefully``'s
  ``text/html`` default plus web-redirect handling) are all removed. v1 renders
  no HTML and is never executed by a browser; CSP is owned solely by Otto's
  response layer (the single policy source).
