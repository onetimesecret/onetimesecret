-- ================================================================
-- Rodauth PostgreSQL Row Level Security Policies (006)
-- Loaded by 006_policies.rb migration
--
-- Enables RLS on sensitive tables to enforce access control at
-- the database level. Actual policies defined based on app roles.
-- ================================================================

-- ================================================================
-- ROW LEVEL SECURITY
-- ================================================================

-- Enable RLS on sensitive tables
ALTER TABLE account_password_hashes ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_otp_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_recovery_codes ENABLE ROW LEVEL SECURITY;

-- ================================================================
-- DOCUMENTATION
-- ================================================================

COMMENT ON TABLE account_previous_password_hashes IS 'Previous password hashes for preventing reuse (created in 001_initial.rb)';

-- ================================================================
-- ACTIVE POLICIES
-- ================================================================

-- Policy: Allow onetime_auth user full access to password hashes
-- Rationale: Rodauth handles authorization at application level
-- Future: Will be refined with tenant context (app.tenant_id) when middleware is implemented
CREATE POLICY rodauth_operations ON account_password_hashes
  FOR ALL TO onetime_auth
  USING (true)
  WITH CHECK (true);

-- Policy: Allow onetime_auth user full access to OTP keys
CREATE POLICY rodauth_operations ON account_otp_keys
  FOR ALL TO onetime_auth
  USING (true)
  WITH CHECK (true);

-- Policy: Allow onetime_auth user full access to recovery codes
CREATE POLICY rodauth_operations ON account_recovery_codes
  FOR ALL TO onetime_auth
  USING (true)
  WITH CHECK (true);

-- ================================================================
-- FUTURE TENANT-BASED POLICY EXAMPLES
-- ================================================================
-- When tenant context middleware is implemented (SET LOCAL app.tenant_id),
-- these policies can be refined to enforce row-level tenant isolation:
--
-- Example: Restrict password hash access by tenant
-- CREATE POLICY tenant_isolation ON account_password_hashes
--   FOR ALL TO onetime_auth
--   USING (id = current_setting('app.tenant_id', true)::BIGINT);
--
-- Example: Restrict OTP access by tenant
-- CREATE POLICY tenant_isolation ON account_otp_keys
--   FOR ALL TO onetime_auth
--   USING (id = current_setting('app.tenant_id', true)::BIGINT);
--
-- Example: Restrict recovery code access by tenant
-- CREATE POLICY tenant_isolation ON account_recovery_codes
--   FOR ALL TO onetime_auth
--   USING (id = current_setting('app.tenant_id', true)::BIGINT);
--
-- See: apps/web/auth/migrations/README.md for RLS implementation roadmap
