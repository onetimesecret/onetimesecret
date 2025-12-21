-- apps/web/auth/migrations/schemas/postgres/setup_auth_db.sql
--
-- PostgreSQL database setup for Rodauth authentication
-- Run this BEFORE first application boot with AUTHENTICATION_MODE=full
--
-- Implements Rodauth's recommended two-user security pattern:
--   - onetime_migrator: Migration user with elevated privileges (DDL operations)
--   - onetime_user: Application user with minimal privileges (DML only)
--
-- Note: Extensions (citext) are created by postgres superuser in this script.
--
-- Usage:
--   psql -U postgres -h localhost -f setup_auth_db.sql
--
-- IMPORTANT: Replace placeholder passwords before running in production!
--   Search for 'CHANGE_ME' and set strong, unique passwords.
--
-- Environment variables after setup:
--   AUTH_DATABASE_URL_MIGRATIONS=postgresql://onetime_migrator:CHANGE_ME@localhost/onetime_auth
--   AUTH_DATABASE_URL=postgresql://onetime_user:CHANGE_ME@localhost/onetime_auth

-- ============================================================================
-- DATABASE CREATION
-- ============================================================================

-- Create the authentication database
CREATE DATABASE onetime_auth;

-- ============================================================================
-- USER CREATION
-- ============================================================================

-- Migration user: Elevated privileges for running Sequel migrations
-- Used by: AUTH_DATABASE_URL_MIGRATIONS
-- Privileges: CREATE TABLE, ALTER TABLE, CREATE FUNCTION, etc.
CREATE USER onetime_migrator WITH PASSWORD 'CHANGE_ME_MIGRATION_PASSWORD';

-- Application user: Minimal privileges for runtime operations
-- Used by: AUTH_DATABASE_URL
-- Privileges: SELECT, INSERT, UPDATE, DELETE on tables; EXECUTE on functions
CREATE USER onetime_user WITH PASSWORD 'CHANGE_ME_APPLICATION_PASSWORD';

-- ============================================================================
-- DATABASE OWNERSHIP & CONNECTION
-- ============================================================================

-- Transfer database ownership to migration user
ALTER DATABASE onetime_auth OWNER TO onetime_migrator;

-- Grant connect privilege to both users
GRANT CONNECT ON DATABASE onetime_auth TO onetime_migrator;
GRANT CONNECT ON DATABASE onetime_auth TO onetime_user;

-- Connect to the new database for schema-level grants
\c onetime_auth

-- ============================================================================
-- EXTENSIONS (Created by postgres superuser before migrations)
-- ============================================================================

-- citext: Case-insensitive text for email columns (required by Rodauth)
-- Must be created by superuser; migration user cannot create extensions
CREATE EXTENSION IF NOT EXISTS citext;

-- pgcrypto: Cryptographic functions (optional, for future use)
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- MIGRATION USER PRIVILEGES (onetime_migrator)
-- ============================================================================

-- Full schema control for migrations (DDL operations)
GRANT ALL ON SCHEMA public TO onetime_migrator;

-- ============================================================================
-- APPLICATION USER PRIVILEGES (onetime_user)
-- ============================================================================

-- Schema usage (required to see objects, but not create them)
GRANT USAGE ON SCHEMA public TO onetime_user;

-- Note: Table/sequence/function grants are applied AFTER migrations run.
-- See the "Post-Migration Grants" section below.

-- ============================================================================
-- DEFAULT PRIVILEGES
-- ============================================================================

-- When onetime_migrator creates objects (during migrations), automatically grant
-- appropriate privileges to onetime_user for runtime access.

-- Tables: DML operations only (no DDL like TRUNCATE, REFERENCES, TRIGGER)
ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO onetime_user;

-- Sequences: Usage for auto-increment columns
ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO onetime_user;

-- Functions: Execute stored procedures and functions
ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO onetime_user;

-- ============================================================================
-- POST-MIGRATION GRANTS (Run after migrations complete)
-- ============================================================================

-- If you have existing tables from a previous setup, run these manually:
--
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO onetime_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO onetime_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO onetime_user;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- After setup, verify with:
--
-- -- Check users exist
-- SELECT usename, usecreatedb, usesuper FROM pg_user
-- WHERE usename IN ('onetime_migrator', 'onetime_user');
--
-- -- Check database ownership
-- SELECT datname, pg_catalog.pg_get_userbyid(datdba) as owner
-- FROM pg_database WHERE datname = 'onetime_auth';
--
-- -- Check extensions
-- SELECT extname, extversion FROM pg_extension
-- WHERE extname IN ('citext', 'pgcrypto');
--
-- -- Check default privileges
-- SELECT defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype, defaclacl
-- FROM pg_default_acl WHERE defaclrole = 'onetime_migrator'::regrole;

-- ============================================================================
-- SECURITY NOTES
-- ============================================================================

-- 1. NEVER commit real passwords to version control
-- 2. Use environment variables or secrets management for passwords
-- 3. The application user (onetime_user) cannot:
--    - CREATE or DROP tables
--    - CREATE or ALTER functions
--    - TRUNCATE tables
--    - Modify schema structure
-- 4. The migration user (onetime_migrator) should only be used during deployments
-- 5. Consider enabling SSL/TLS for database connections in production
-- 6. Review pg_hba.conf to restrict connection sources
-- 7. For Row Level Security (RLS):
--    - Application user (onetime_user) always respects RLS policies
--    - Migration user (onetime_migrator) may bypass RLS as table owner
--    - Use FORCE ROW LEVEL SECURITY if migrations need policy enforcement
