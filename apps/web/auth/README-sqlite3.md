Initialize SQLite3 Database for Rodauth

1. Navigate to the auth directory

cd apps/web/auth

2. Install dependencies (if not already done)

bundle install

3. Run the migration

ruby migrate.rb

4. Verify the database was created

# Check if the database file exists
ls -la auth.db

# View the tables
sqlite3 auth.db ".tables"

# View table structure
sqlite3 auth.db ".schema accounts"

5. Optional: View the schema in detail

RACK_ENV=development ruby migrate.rb

This will show you all the tables and their structure.

Expected Output

When you run ruby migrate.rb, you should see:
Connecting to database: sqlite://auth.db
Running database migrations...
Database migrations completed successfully!
Current schema version: 001_create_rodauth_base.rb

Database schema:
  accounts:
    id: integer NOT NULL
    email: varchar(255) NOT NULL
    status_id: integer NOT NULL
    created_at: timestamp NOT NULL
    updated_at: timestamp NOT NULL
    last_login_ip: varchar(255) NULL
    last_login_at: timestamp NULL

  account_password_hashes:
    id: integer NOT NULL
    password_hash: varchar(255) NOT NULL

  ... (other tables)

Tables Created

The migration creates these tables:
- accounts - Main user accounts
- account_password_hashes - Password storage (separate for security)
- account_verification_keys - Email verification
- account_password_reset_keys - Password reset functionality
- account_login_failures - Brute force protection
- account_lockouts - Account lockouts
- account_remember_keys - "Remember me" functionality
- account_active_session_keys - Active session tracking
