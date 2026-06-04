-- apps/web/auth/migrations/schemas/postgres/initialize_test_db.sql
--
-- Provisions the test PostgreSQL database with least-privilege role
-- separation. Run as superuser against an existing database:
--
--   psql -U postgres -d onetime_auth_test -f apps/web/auth/migrations/schemas/postgres/initialize_test_db.sql
--
-- Used by:
--   - install-test.sh        (local development)
--   - .github/workflows/ci.yml
--   - .github/workflows/migration-tests.yml
--
-- Role model:
--   postgres           superuser — provisioning only, never in app URLs
--   onetime_migrator   DDL + CREATEDB — owns tables, runs migrations
--   onetime_user       DML only — runtime app, no schema mutation
--   onetime_migrator_test  unprivileged — migration permission tests

-- Abort if the database name does not contain "test" — prevents
-- accidental execution against staging or production.
DO $$
BEGIN
  IF current_database() NOT LIKE '%test%' THEN
    RAISE EXCEPTION 'Refusing to run: database "%" does not contain "test"', current_database();
  END IF;
END
$$;

-- Reset schema so stale superuser-owned objects don't block the migrator.
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

------------------------------------------------------------------------
-- 1. Create roles (idempotent)
------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'onetime_user') THEN
    CREATE USER onetime_user WITH PASSWORD 'testpass';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'onetime_migrator') THEN
    CREATE USER onetime_migrator WITH PASSWORD 'migratepass' CREATEDB;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'onetime_migrator_test') THEN
    CREATE USER onetime_migrator_test WITH PASSWORD 'testpass';
  END IF;
END
$$;

------------------------------------------------------------------------
-- 2. Database-level grants
------------------------------------------------------------------------

-- Use the current database name so the script works regardless of
-- whether the database is called onetime_auth_test or something else.
DO $$
DECLARE
  dbname text := current_database();
BEGIN
  EXECUTE format('GRANT CONNECT ON DATABASE %I TO onetime_user', dbname);
  EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO onetime_migrator', dbname);
END
$$;

------------------------------------------------------------------------
-- 3. Schema-level grants
------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO onetime_user;
GRANT ALL ON SCHEMA public TO onetime_migrator;
GRANT USAGE ON SCHEMA public TO onetime_migrator_test;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

------------------------------------------------------------------------
-- 4. Default privileges — tables created by onetime_migrator are
--    automatically DML-accessible to onetime_user.
------------------------------------------------------------------------

ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO onetime_user;
ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO onetime_user;
ALTER DEFAULT PRIVILEGES FOR ROLE onetime_migrator IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO onetime_user;
