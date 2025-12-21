-- Buggy version for testing AuthTriggerValidator (PostgreSQL)
-- This file intentionally contains the bug that was fixed in commit d72db567e
-- The trigger references account_id column which doesn't exist in account_activity_times

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

CREATE TRIGGER trigger_update_last_login_time
    AFTER INSERT ON account_authentication_audit_logs
    FOR EACH ROW
    EXECUTE FUNCTION update_last_login_time();
