.. A new scriv changelog fragment.

Changed
-------

- Reading a secret no longer changes it: ``GET /secret/:identifier`` and
  ``GET /secret/:identifier/status`` (v2 and v3) previously advanced the
  secret's lifecycle state from ``new`` to ``previewed`` as a side effect of
  the read, violating HTTP safe-method semantics and polluting the
  creator-facing "was my secret seen?" signal with mechanical fetches. The
  lifecycle state now only advances on a genuine reveal or burn. (#3633)

Added
-----

- Access telemetry on the receipt: every fetch of a secret's link or status
  is recorded as an append-only event on the receipt's access timeline
  (capped, expires with the receipt). The receipt endpoints now surface the
  derived aggregates in their details payload — ``view_count`` (previously
  always ``null``) plus new ``first_access`` and ``last_access`` epoch
  timestamps — so creators can see whether and when a link was accessed,
  even after the secret itself is consumed. (#3633)
