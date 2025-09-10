-- Initialize databases for OneTimeSecret and Authentication Service


-- Create users
CREATE USER onetime WITH ENCRYPTED PASSWORD 'password';
CREATE USER auth_user WITH ENCRYPTED PASSWORD 'auth_password';

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE onetime TO onetime;
GRANT ALL PRIVILEGES ON DATABASE onetime_auth TO auth_user;

-- Connect to auth database to set up extensions
\c onetime_auth;
CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO auth_user;
