-- apps/web/auth/migrations/schemas/postgres/initialize_auth_db.sql
--
-- PostgreSQL database setup for Rodauth authentication
-- Run this BEFORE first application boot with AUTHENTICATION_MODE=full
--
-- Implements Rodauth's recommended two-user security pattern:
--   - ots_migrator: Migration user with elevated privileges (DDL operations)
--   - ots_user: Application user with minimal privileges (DML only)
--
-- Note: Extensions (citext) are created by postgres superuser in this script.
--
-- Usage:
--   psql -U postgres -h localhost -f initialize_auth_db.sql
--
-- IMPORTANT: Replace placeholder passwords before running in production!
--   Search for 'CHANGE_ME' and set strong, unique passwords.
--
-- Environment variables after setup:
--   AUTH_DATABASE_URL_MIGRATIONS=postgresql://ots_migrator:CHANGE_ME@localhost/onetime_authdb
--   AUTH_DATABASE_URL=postgresql://ots_user:CHANGE_ME@localhost/onetime_authdb

-- ============================================================================
-- DATABASE CREATION
-- ============================================================================

-- Create the authentication database
CREATE DATABASE onetime_authdb;

-- ============================================================================
-- USER CREATION
-- ============================================================================

-- Migration user: Elevated privileges for running Sequel migrations
-- Used by: AUTH_DATABASE_URL_MIGRATIONS
-- Privileges: CREATE TABLE, ALTER TABLE, CREATE FUNCTION, etc.
CREATE USER ots_migrator WITH PASSWORD 'CHANGE_ME_MIGRATION_PASSWORD';

-- Application user: Minimal privileges for runtime operations
-- Used by: AUTH_DATABASE_URL
-- Privileges: SELECT, INSERT, UPDATE, DELETE on tables; EXECUTE on functions
CREATE USER ots_user WITH PASSWORD 'CHANGE_ME_APPLICATION_PASSWORD';

-- ============================================================================
-- DATABASE OWNERSHIP & CONNECTION
-- ============================================================================

-- Transfer database ownership to migration user
ALTER DATABASE onetime_authdb OWNER TO ots_migrator;

-- Grant connect privilege to both users
GRANT CONNECT ON DATABASE onetime_authdb TO ots_migrator;
GRANT CONNECT ON DATABASE onetime_authdb TO ots_user;

-- Connect to the new database for schema-level grants
\c onetime_authdb

-- ============================================================================
-- EXTENSIONS (Created by postgres superuser before migrations)
-- ============================================================================

-- citext: Case-insensitive text for email columns (required by Rodauth)
-- Must be created by superuser; migration user cannot create extensions
CREATE EXTENSION IF NOT EXISTS citext;

-- pgcrypto: Cryptographic functions (optional, for future use)
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- MIGRATION USER PRIVILEGES (ots_migrator)
-- ============================================================================

-- Full schema control for migrations (DDL operations)
GRANT ALL ON SCHEMA public TO ots_migrator;

-- ============================================================================
-- APPLICATION USER PRIVILEGES (ots_user)
-- ============================================================================

-- Schema usage (required to see objects, but not create them)
GRANT USAGE ON SCHEMA public TO ots_user;

-- Note: Table/sequence/function grants are applied AFTER migrations run.
-- See the "Post-Migration Grants" section below.

-- ============================================================================
-- DEFAULT PRIVILEGES
-- ============================================================================

-- When ots_migrator creates objects (during migrations), automatically grant
-- appropriate privileges to ots_user for runtime access.

-- Tables: DML operations only (no DDL like TRUNCATE, REFERENCES, TRIGGER)
ALTER DEFAULT PRIVILEGES FOR ROLE ots_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ots_user;

-- Sequences: Usage for auto-increment columns
ALTER DEFAULT PRIVILEGES FOR ROLE ots_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO ots_user;

-- Functions: Execute stored procedures and functions
ALTER DEFAULT PRIVILEGES FOR ROLE ots_migrator IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO ots_user;

-- ============================================================================
-- POST-MIGRATION GRANTS (Run after migrations complete)
-- ============================================================================

-- If you have existing tables from a previous setup, run these manually:
--
-- GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ots_user;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ots_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ots_user;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- After setup, verify with:
--
-- -- Check users exist
-- SELECT usename, usecreatedb, usesuper FROM pg_user
-- WHERE usename IN ('ots_migrator', 'ots_user');
--
-- -- Check database ownership
-- SELECT datname, pg_catalog.pg_get_userbyid(datdba) as owner
-- FROM pg_database WHERE datname = 'onetime_authdb';
--
-- -- Check extensions
-- SELECT extname, extversion FROM pg_extension
-- WHERE extname IN ('citext', 'pgcrypto');
--
-- -- Check default privileges
-- SELECT defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype, defaclacl
-- FROM pg_default_acl WHERE defaclrole = 'ots_migrator'::regrole;

-- ============================================================================
-- SECURITY NOTES
-- ============================================================================

-- 1. NEVER commit real passwords to version control
-- 2. Use environment variables or secrets management for passwords
-- 3. The application user (ots_user) cannot:
--    - CREATE or DROP tables
--    - CREATE or ALTER functions
--    - TRUNCATE tables
--    - Modify schema structure
-- 4. The migration user (ots_migrator) should only be used during deployments
-- 5. Consider enabling SSL/TLS for database connections in production
-- 6. Review pg_hba.conf to restrict connection sources
-- 7. For Row Level Security (RLS):
--    - Application user (ots_user) always respects RLS policies
--    - Migration user (ots_migrator) may bypass RLS as table owner
--    - Use FORCE ROW LEVEL SECURITY if migrations need policy enforcement

-- ============================================================================
-- RESET / CLEANUP (for testing from scratch)
-- ============================================================================
--
-- PostgreSQL roles are cluster-wide, so dropping the database alone won't
-- remove them. To fully reset:
--
/*

-- Drop databases
DROP DATABASE IF EXISTS onetime_authdb;
DROP DATABASE IF EXISTS onetime_authdb_test;

-- Drop roles (must drop after databases that depend on them)
DROP ROLE IF EXISTS ots_user;
DROP ROLE IF EXISTS ots_migrator;

-- If you want to keep onetime_authdb_test, reassign ownership first:

REASSIGN OWNED BY ots_user TO postgres;
REASSIGN OWNED BY ots_migrator TO postgres;

REVOKE ALL PRIVILEGES ON DATABASE onetime_authdb_test FROM ots_user;
REVOKE ALL PRIVILEGES ON DATABASE onetime_authdb_test FROM ots_migrator;

DROP ROLE IF EXISTS ots_user;
DROP ROLE IF EXISTS ots_migrator;

*/
