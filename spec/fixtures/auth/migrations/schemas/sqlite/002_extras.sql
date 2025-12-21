-- Buggy version for testing AuthTriggerValidator
-- This file intentionally contains the bug that was fixed in commit d72db567e
-- The trigger references account_id column which doesn't exist in account_activity_times

CREATE TRIGGER update_login_activity
AFTER INSERT ON account_authentication_audit_logs
WHEN NEW.message LIKE '%login%successful%'
BEGIN
    INSERT OR REPLACE INTO account_activity_times (account_id, last_login_at, last_activity_at)
    VALUES (NEW.account_id, NEW.at, NEW.at);
END;
