-- ================================================================
-- Rodauth SQLite Row Level Security Policies (006)
-- Loaded by 006_policies.rb migration
--
-- SQLite Limitation: No Row Level Security
-- ================================================================
--
-- SQLite does not support Row Level Security (RLS) policies.
-- Application-level access control must be implemented in Ruby code.
--
-- PostgreSQL equivalent that cannot be implemented:
-- - ALTER TABLE account_password_hashes ENABLE ROW LEVEL SECURITY;
-- - ALTER TABLE account_otp_keys ENABLE ROW LEVEL SECURITY;
-- - ALTER TABLE account_recovery_codes ENABLE ROW LEVEL SECURITY;
--
-- Security recommendations for SQLite:
-- 1. Use connection-level restrictions in application code
-- 2. Implement data access policies in Sequel models
-- 3. Use separate database connections with limited permissions where possible
-- 4. Validate all queries through ORM layer (avoid raw SQL)
-- 5. Consider table-level encryption for sensitive columns
--
-- ================================================================
-- DOCUMENTATION
-- ================================================================
--
-- SQLite Limitation: No COMMENT ON Syntax
--
-- Table descriptions (for reference):
-- - account_previous_password_hashes: Previous password hashes for preventing reuse

-- ================================================================
-- POLICY EXAMPLES (For reference - must be implemented in application)
-- ================================================================

/*
-- PostgreSQL policies that must be implemented at application level in SQLite:

-- Example: Restrict password hash access to password role
-- Implementation: Check user role before allowing access to password_hash column

-- Example: Restrict OTP access to authenticated sessions
-- Implementation: Filter queries by current_account_id in application code

-- Example: Restrict recovery code access to account owner
-- Implementation: Add WHERE clause: account_id = current_account_id

-- Note: All access control must be enforced at the application layer
-- in SQLite. Use Sequel model scopes and before hooks for consistency.
*/

-- This file intentionally contains no executable SQL.
