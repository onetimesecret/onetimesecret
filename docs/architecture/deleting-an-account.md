
After #4395, all three flows funnel through Auth::Operations::TeardownAccount, which runs the same ordered teardown: revoke sessions → close/strip the SQL auth identity (full mode only) → delete the Redis Customer last. What differs per flow is session-revoke variant, auditing, and whether SQL is touched.

Common end state (the teardown contract)

1. Sessions revoked first — before either store is torn down, so no live session outlives the record.
2. SQL auth identity (full mode only) — RemoveAuthenticationData runs with retain_account: true, so the accounts row is not hard-deleted. It is:
   - flipped to status_id = CLOSED (status 3), a retained closed row;
   - stripped of every credential/MFA/pending-token table (password hashes, reset/verify/login-change keys, JWT refresh, remember, webauthn, otp, recovery/sms, identities, active-session keys, etc.);
   - audit logs preserved (account_authentication_audit_logs is excluded from the delete when retaining).
   - In simple mode this phase is a no-op (full_auth_mode? false) — there is no SQL identity.
3. Redis Customer deleted last — DestroyCustomerRecord calls customer.destroy! (model + class indexes). Ordering is deliberate: SQL closure happens before the irreversible Redis delete, and in the hook path a Redis failure aborts the SQL transaction.

Net: Redis customer is fully gone; the SQL identity survives as a closed, credential-less, audit-bearing tombstone (full mode).

The three flows

Flow: Self-service, simple mode
Entry: DestroyAccount logic (DELETE account API); password checked against Redis Customer.passphrase
Session revoke: RevokeAllForCustomerExceptCurrent(except: nil) → all
SQL phase: none (no auth DB)
Audit: none
────────────────────────────────────────
Flow: Self-service, full mode
Entry: Rodauth /auth/close-account → after_close_account hook → TeardownAccount(account:, db:)
Session revoke: same, all
SQL phase: retained closed row (runs inside Rodauth's txn, shared db)
Audit: none (Rodauth's own audit log is what's preserved)
────────────────────────────────────────
Flow: Admin / colonel
Entry: PurgeUser → Customers::Purge → TeardownAccount(customer:, actor:, reason:); also bin/ots customers purge-one
Session revoke: audited RevokeAllForCustomer → records session.revoke_all
SQL phase: retained closed row
Audit: Customers::Purge records customer.purge ColonelAuditEvent, fail-closed (unwritable audit fails the purge)

Key branch points inside the orchestrator:
- actor presence selects the audited (RevokeAllForCustomer) vs. plain (RevokeAllForCustomerExceptCurrent) revoke — self-service never writes the colonel audit trail.
- customer: vs account: — self-service simple passes the resolved Customer; the Rodauth hook passes the account hash and TeardownAccount resolves the customer by external_id, falling back to email. In the account: + full-mode case, the result is :success even if no Redis customer is found, so closing an account whose Redis side is already gone doesn't fail.

One thing outside "the 3 flows"

The bulk bin/ots customers purge inactivity sweep deliberately does not go through TeardownAccount/Purge — it deletes via the bare DestroyCustomerRecord primitive (no SQL teardown, no per-record audit) to avoid flooding the capped audit set. So "any of the 3 code flows" = the two self-service paths + colonel purge; the maintenance sweep is a separate, intentionally lighter path.
