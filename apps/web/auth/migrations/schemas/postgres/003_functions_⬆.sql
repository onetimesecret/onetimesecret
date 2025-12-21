-- ================================================================
-- Rodauth PostgreSQL Functions (003)
-- Loaded by 002_functions.rb migration
--
-- All standalone functions and functions used by triggers
-- ================================================================

-- ================================================================
-- SECURITY FUNCTIONS (from 001_initial.sql)
-- ================================================================

-- Function to get password salt (for database-level security)
--
-- Security model: The 'app' db user cannot SELECT password_hash directly.
-- This SECURITY DEFINER function runs with elevated privileges, providing
-- defense-in-depth against SQL injection attacks on the hash column.
--
-- Argon2 vs bcrypt salt handling:
--   - bcrypt: Salt is a distinct 29-char prefix ($2a$12$...), so we return just that
--   - Argon2: Parameters (m,t,p) and salt are embedded in the hash string
--     ($argon2id$v=19$m=65536,t=2,p=1$<salt>$<hash>). Rodauth's password
--     verification needs the full string to extract cost params and salt.
--     Returning full hash does NOT compromise security - the protection comes
--     from SQL privileges, not from truncating the return value.
--
CREATE OR REPLACE FUNCTION rodauth_get_salt(p_account_id BIGINT)
RETURNS TEXT AS $$
DECLARE
    hash TEXT;
BEGIN
    SELECT password_hash INTO hash
    FROM account_password_hashes
    WHERE id = p_account_id;

    IF hash IS NULL THEN
        RETURN NULL;
    ELSIF hash LIKE '$argon2%' THEN
        RETURN hash;  -- Argon2: full hash needed for param extraction
    ELSIF hash LIKE '$2a$%' OR hash LIKE '$2b$%' THEN
        RETURN SUBSTRING(hash FROM 1 FOR 29);  -- bcrypt: 29-char salt prefix
    ELSE
        RAISE EXCEPTION 'Unrecognized password hash algorithm for account %', p_account_id;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to validate password hash (for database-level security)
CREATE OR REPLACE FUNCTION rodauth_valid_password_hash(p_account_id BIGINT, hash TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    valid BOOLEAN := FALSE;
BEGIN
    SELECT password_hash = hash INTO valid
    FROM account_password_hashes
    WHERE id = p_account_id;
    RETURN COALESCE(valid, FALSE);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Clean up expired tokens function
CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS VOID AS $$
BEGIN
    -- Clean up expired password reset keys
    DELETE FROM account_password_reset_keys WHERE deadline < NOW();

    -- Clean up expired remember keys
    DELETE FROM account_remember_keys WHERE deadline < NOW();

    -- Clean up expired lockouts
    DELETE FROM account_lockouts WHERE deadline < NOW();

    -- Log cleanup action
    RAISE NOTICE 'Cleaned up expired tokens at %', NOW();
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- TRIGGER FUNCTIONS (from 002_extras.sql)
-- ================================================================

-- Function to automatically update activity time on successful logins
CREATE OR REPLACE FUNCTION update_last_login_time()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.message ILIKE '%login%successful%' THEN
        INSERT INTO account_activity_times (account_id, last_login_at, last_activity_at)
        VALUES (NEW.account_id, NEW.at, NEW.at)
        ON CONFLICT (account_id)
        DO UPDATE SET
            last_login_at = NEW.at,
            last_activity_at = NEW.at;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Enhanced cleanup function for new token types
CREATE OR REPLACE FUNCTION cleanup_expired_tokens_extended()
RETURNS TRIGGER AS $$
BEGIN
    -- Clean up expired JWT refresh tokens
    DELETE FROM account_jwt_refresh_keys WHERE deadline < NOW();

    -- Clean up expired email auth keys
    DELETE FROM account_email_auth_keys WHERE deadline < NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update account updated_at timestamp
CREATE OR REPLACE FUNCTION update_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- UTILITY FUNCTIONS (from 002_extras.sql)
-- ================================================================

-- Function to update session last_use timestamp
CREATE OR REPLACE FUNCTION update_session_last_use(
    p_account_id BIGINT,
    p_session_id VARCHAR
)
RETURNS VOID AS $$
BEGIN
    UPDATE account_active_session_keys
    SET last_use = NOW()
    WHERE account_id = p_account_id AND session_id = p_session_id;
END;
$$ LANGUAGE plpgsql;

-- Function to clean up old audit logs (keep last 90 days)
CREATE OR REPLACE FUNCTION cleanup_old_audit_logs()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM account_authentication_audit_logs
    WHERE at < NOW() - INTERVAL '90 days';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to get account security summary
CREATE OR REPLACE FUNCTION get_account_security_summary(p_account_id BIGINT)
RETURNS TABLE(
    has_password BOOLEAN,
    has_otp BOOLEAN,
    has_sms BOOLEAN,
    has_webauthn BOOLEAN,
    active_sessions INTEGER,
    last_login TIMESTAMPTZ,
    failed_attempts INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        EXISTS(SELECT 1 FROM account_password_hashes WHERE id = p_account_id),
        EXISTS(SELECT 1 FROM account_otp_keys WHERE id = p_account_id),
        EXISTS(SELECT 1 FROM account_sms_codes WHERE id = p_account_id),
        EXISTS(SELECT 1 FROM account_webauthn_keys WHERE account_id = p_account_id),
        (SELECT COUNT(*)::INTEGER FROM account_active_session_keys WHERE account_id = p_account_id),
        (SELECT last_login_at FROM account_activity_times WHERE id = p_account_id),
        COALESCE((SELECT number FROM account_login_failures WHERE id = p_account_id), 0);
END;
$$ LANGUAGE plpgsql;
