-- apps/web/auth/migrations/schemas/postgres/setup_auth_db.sql
--
-- PostgreSQL database setup for Rodauth authentication
-- Run this BEFORE first application boot with AUTHENTICATION_MODE=full
--
-- Usage:
--   psql -U postgres -h localhost -f setup_auth_db.sql

-- Create database for authentication
CREATE DATABASE onetime_auth OWNER postgres;

-- Create application user
CREATE USER onetime_user WITH PASSWORD 'onetime_user';

-- Grant database privileges
GRANT ALL PRIVILEGES ON DATABASE onetime_auth TO onetime_user;

-- Connect to the database to grant schema privileges
\c onetime_auth

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO onetime_user;

-- Grant usage and create on public schema (for tables, sequences, etc.)
GRANT USAGE, CREATE ON SCHEMA public TO onetime_auth;

-- Ensure default privileges for future objects created by postgres role
-- This ensures migrations run as superuser automatically grant access to onetime_user
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO onetime_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO onetime_user;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO onetime_user;
