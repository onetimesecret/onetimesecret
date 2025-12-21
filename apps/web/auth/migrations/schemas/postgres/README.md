## PostgreSQL Setup

**IMPORTANT:** Run this setup script BEFORE first application boot with `AUTHENTICATION_MODE=full`.

### Running the Setup

```bash
psql -U postgres -h localhost -f setup_auth_db.sql
```

This script:
- Creates the `onetime_auth_test` database
- Creates the `onetime_auth` user
- Grants schema privileges
- Configures default privileges for objects created by superuser migrations

### After Setup

Once the database and user are configured, the application will automatically:
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
