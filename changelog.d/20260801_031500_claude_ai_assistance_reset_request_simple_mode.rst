.. A new scriv changelog fragment.

AI Assistance
-------------

- Simple-mode reset-request rate limiting implemented end-to-end with Claude
  Code: the limiter call site, the integration and unit coverage, and the
  operator/audit documentation. The specs were then hardened against an
  adversarial review pass that found two of them passing under mutation, and
  that pass also surfaced the invalid-UTF-8 constructor path that bypassed the
  new counter.

- A follow-up review pass, also with Claude Code, examined four reservations
  raised against the change. Two did not survive contact with the code and were
  dropped: keying the tight tier on IP alone is correct here rather than
  inconsistent, and the raise_concerns/process lifecycle is enforced at a
  controller chokepoint rather than by convention. The pass instead found the
  registry gap that left a lockout unclearable, a documented recovery command
  that only printed text without touching the datastore, and a hint whose
  production call site no test pinned. Recovery procedures in this changeset
  were confirmed by clearing a seeded lockout key, not by reading help output.
