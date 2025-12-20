## PostgreSQL Setup


### Running the Setup

Here's the SQL to run as the PostgreSQL superuser before first boot:

```bash
psql -U postgres -h localhost -f setup_auth_db.sql
```


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
