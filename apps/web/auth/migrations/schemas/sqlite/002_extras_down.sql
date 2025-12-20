-- ================================================================
-- Rollback Extended Features - SQLite
-- Drops only database-specific features created in 002_extras.sql
-- Tables are dropped in 002_extras.rb migration
-- ================================================================

-- Drop triggers first
DROP TRIGGER IF EXISTS update_login_activity;
DROP TRIGGER IF EXISTS cleanup_expired_jwt_refresh_tokens;

-- Drop views
DROP VIEW IF EXISTS recent_auth_events;
DROP VIEW IF EXISTS account_security_overview_enhanced;
