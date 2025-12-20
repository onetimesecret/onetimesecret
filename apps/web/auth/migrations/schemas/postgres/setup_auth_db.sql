-- Create database for authentication
CREATE DATABASE onetime_auth_test OWNER postgres;

-- Create application user
CREATE USER onetime_auth WITH PASSWORD 'onetime_auth';

-- Grant database privileges
GRANT ALL PRIVILEGES ON DATABASE onetime_auth_test TO onetime_auth;

-- Connect to the database to grant schema privileges
\c onetime_auth_test

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO onetime_auth;

-- Grant usage and create on public schema (for tables, sequences, etc.)
GRANT USAGE, CREATE ON SCHEMA public TO onetime_auth;

-- Ensure default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO onetime_auth;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO onetime_auth;
