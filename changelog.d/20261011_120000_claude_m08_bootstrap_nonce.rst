.. A new scriv changelog fragment.

Security
--------

- The page bootstrap payload (``window.__BOOTSTRAP_ME__`` and the
  ``/bootstrap/me`` response) no longer carries the CSP nonce, so an
  HTML-injection flaw has one less place to read it from and reuse it under
  the nonce-only Content Security Policy. The DNS widget now reads the nonce
  from the page's own nonce'd elements instead. (RISK-2026-08-14-M08)
