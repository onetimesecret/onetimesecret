-- ================================================================
-- Rodauth PostgreSQL Row Level Security Policies Rollback (006)
-- ================================================================

-- Disable RLS on sensitive tables
ALTER TABLE account_recovery_codes DISABLE ROW LEVEL SECURITY;
ALTER TABLE account_otp_keys DISABLE ROW LEVEL SECURITY;
ALTER TABLE account_password_hashes DISABLE ROW LEVEL SECURITY;
