## PostgreSQL Setup

Here's the SQL to run as the PostgreSQL superuser before first boot:

```sql
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
```

### Running the Setup

Run as a file:

```bash
psql -U postgres -h localhost -f setup_auth_db.sql
```

Or interactively:

```bash
psql -U postgres -h localhost
```

Then paste the SQL commands above.

### Automatic Setup

> **Note:** The application will automatically:
> - Create the `citext` extension (requires superuser or extension creation privileges)
> - Run all Rodauth migrations
> - Create all 23 authentication tables

### Optional: Extension Creation Privileges

If you want the regular user to create extensions, grant additional privileges:

```sql
ALTER USER onetime_auth CREATEDB;

-- Or for just this database:
\c onetime_auth_test
GRANT CREATE ON DATABASE onetime_auth_test TO onetime_auth;
```
