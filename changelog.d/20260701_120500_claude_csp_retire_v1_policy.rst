.. A new scriv changelog fragment.

Removed
-------

- The deprecated v1 API no longer emits browser-security machinery. Its
  hand-rolled Content-Security-Policy and the per-request nonce it generated
  are removed: v1 serves JSON only (never executed by a browser), and CSP is
  now owned solely by Otto's response layer (the single policy source).
