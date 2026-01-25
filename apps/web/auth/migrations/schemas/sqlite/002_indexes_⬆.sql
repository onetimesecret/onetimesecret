-- ================================================================
-- Rodauth SQLite Performance Indexes (002)
-- Loaded by 002_indexes.rb migration
--
-- Creates indexes immediately after table creation for optimal
-- query performance on frequently accessed columns.
-- ================================================================

-- ================================================================
-- PERFORMANCE INDEXES
-- ================================================================

-- JWT refresh keys - lookup by account and expiration
CREATE INDEX idx_jwt_refresh_keys_account_id ON account_jwt_refresh_keys(account_id);
CREATE INDEX idx_jwt_refresh_keys_deadline ON account_jwt_refresh_keys(deadline);

-- Activity tracking - lookup by last activity and login times
CREATE INDEX idx_activity_times_last_activity ON account_activity_times(last_activity_at);
CREATE INDEX idx_activity_times_last_login ON account_activity_times(last_login_at);

-- Email auth keys - expiration cleanup
CREATE INDEX idx_email_auth_keys_deadline ON account_email_auth_keys(deadline);

-- Password history - prevent reuse lookups
CREATE INDEX idx_previous_password_hashes_account_id ON account_previous_password_hashes(account_id);
