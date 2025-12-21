Debugging Complete - RLS Issue Resolved

Root Cause:
Migration 006 enabled Row Level Security on account_password_hashes, account_otp_keys, and account_recovery_codes tables but created zero policies. When RLS is enabled without policies, PostgreSQL denies all operations by default.

Fix Applied:
Created permissive policies in apps/web/auth/migrations/schemas/postgres/006_policies_⬆.sql allowing the onetime_auth database user to perform all operations on RLS-protected tables.

Files Modified:
- apps/web/auth/migrations/schemas/postgres/006_policies_⬆.sql - Added CREATE POLICY statements
- apps/web/auth/migrations/schemas/postgres/006_policies_⬇.sql - Added DROP POLICY statements for rollback

Policies Created:
CREATE POLICY rodauth_operations ON account_password_hashes FOR ALL TO onetime_auth USING (true);
CREATE POLICY rodauth_operations ON account_otp_keys FOR ALL TO onetime_auth USING (true);
CREATE POLICY rodauth_operations ON account_recovery_codes FOR ALL TO onetime_auth USING (true);

Verification:
# Confirm policies are active
psql -U postgres -h localhost -d onetime_auth -c \
  "SELECT tablename, policyname, roles FROM pg_policies WHERE tablename LIKE 'account%';"

Next Steps:
The permissive policies allow Rodauth to function now. Per the RLS implementation plan (memory 1100-issue-1876-rls-implementation-technical-depth), these can later be refined to enforce tenant-based isolation when the TenantContext middleware is implemented with SET LOCAL app.tenant_id.

Try the account creation flow now - it should work.
