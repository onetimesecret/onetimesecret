.. A new scriv changelog fragment.

Removed
-------

- The deprecated v1 API no longer defines its own hand-rolled
  Content-Security-Policy. CSP is now owned solely by Otto's response layer
  (the single policy source), so the parallel policy definition in the v1
  helpers has been removed.
