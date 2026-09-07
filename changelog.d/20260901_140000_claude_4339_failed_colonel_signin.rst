.. A new scriv changelog fragment.

Security
--------

- Failed sign-ins against existing Colonel accounts are now recorded as
  ``colonel.signin_failed`` in both authentication modes. The audit event uses
  an obscured account email and coarse failure details (#4339).

Changed
-------

- Failed Colonel sign-ins use a separate 7-day telemetry stream, so attempt
  volume cannot evict destructive-action records from the operator trail
  (#4339).
