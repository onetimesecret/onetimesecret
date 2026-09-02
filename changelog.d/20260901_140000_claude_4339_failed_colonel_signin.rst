.. A new scriv changelog fragment.

Security
--------

- Failed sign-in attempts against an **admin (colonel) account** are now
  recorded in the admin audit trail as ``colonel.signin_failed`` (#4339).
  Successful colonel sign-ins were already audited; failures recorded nothing
  at all, so a brute-force against an admin account left no queryable trace —
  the highest-signal security event the trail could hold was the one it did not
  hold. Both authentication modes emit it: full mode from the Rodauth
  login-failure hook, simple mode from its credential-rejection funnel.

- Only attempts against **accounts that actually exist and actually hold the
  colonel role** are recorded. Submitting an arbitrary address mints nothing,
  so the trail stays a curated signal ("a real admin account is being
  targeted") rather than a log of whatever strings were typed into the login
  form.

- The event names the account by its **obscured** email, never the full
  address and never an internal identifier — the audit trail must not become
  an account-enumeration oracle, and events are shipped to the external audit
  sink at write time. Recorded detail is limited to the authentication mode and
  a coarse failure reason; the client IP stays in the authentication log line,
  where it already was.

Changed
-------

- These events land in the audit store's **anonymous-telemetry stream**
  (newest 1,000, 7-day retention), not the operator trail — so no volume of
  failed sign-ins can push a purge, role change or suspension out of the
  record. Operators reading the audit log can filter on ``colonel.signin`` for
  sign-ins and ``colonel.signin_failed`` for attempts, or on ``colonel`` for
  both.

- The Rodauth authentication audit log
  (``account_authentication_audit_logs``) is unchanged; this is the operator
  audit trail only.
