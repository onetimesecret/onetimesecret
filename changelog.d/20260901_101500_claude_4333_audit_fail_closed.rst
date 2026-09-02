.. A new scriv changelog fragment.

Security
--------

- Destructive operator actions now fail closed when their audit event cannot
  be written (#4333). Purging a customer, deleting an organization, changing a
  role, revoking or deleting sessions, suspending an account, deleting a
  secret, purging a dead-letter queue, removing a custom domain and removing a
  membership all previously reported success even when the operator trail
  write failed, leaving an untraceable destructive action behind. They now
  surface a hard failure naming the verb and target instead.

- The mutation itself is not rolled back — nearly every operation records after
  it mutates, so failing closed changes what the operator is *told*, not what
  happened. Treat such a failure as "this action needs to be reconstructed",
  not as "this action did not run".

- Additive and corrective operations (create, add, repair, reconcile, verify,
  banner, plan and entitlement changes, email tooling) are unchanged and stay
  fail-open, as does the separate security-telemetry trail: writers an
  unauthenticated caller can drive must never gain an abort primitive.
