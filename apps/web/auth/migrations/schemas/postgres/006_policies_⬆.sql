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
-- POLICY EXAMPLES (To be implemented based on application roles)
-- ================================================================

/*
-- Example: Restrict password hash access to password role
CREATE POLICY password_access ON account_password_hashes
  FOR ALL TO password_user USING (true);

-- Example: Restrict OTP access to authenticated sessions
CREATE POLICY otp_access ON account_otp_keys
  FOR ALL TO auth_user
  USING (id = current_setting('app.current_account_id')::BIGINT);

-- Example: Restrict recovery code access to account owner
CREATE POLICY recovery_code_access ON account_recovery_codes
  FOR ALL TO auth_user
  USING (id = current_setting('app.current_account_id')::BIGINT);

-- Note: Policies should be created based on your specific security model
-- and the database roles/users configured in your environment.
*/
