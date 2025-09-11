Core Schema Requirements

Essential Tables

1. Account Statuses Table (if using status-based verification):
create_table(:account_statuses) do
  Integer :id, primary_key: true
  String :name, null: false, unique: true
end
# Data: [1, 'Unverified'], [2, 'Verified'], [3, 'Closed']

2. Accounts Table (main user table):
create_table(:accounts) do
  primary_key :id, type: :Bignum
  foreign_key :status_id, :account_statuses, null: false, default: 1

  # PostgreSQL with citext extension for case-insensitive emails
  if database_type == :postgres
    citext :email, null: false
    constraint :valid_email, email: /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/
  else
    String :email, null: false
  end

  # Unique index with status filtering for PostgreSQL
  if supports_partial_indexes?
    index :email, unique: true, where: {status_id: [1, 2]}
  else
    index :email, unique: true
  end
end

3. Password Hashes Table (separate for security):
create_table(:account_password_hashes) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  String :password_hash, null: false
end

Feature-Specific Tables (Based on Your Enabled Features)

For reset_password feature:
create_table(:account_password_reset_keys) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  String :key, null: false
  DateTime :deadline, deadline_opts[1]
  DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
end

For remember feature:
create_table(:account_remember_keys) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  String :key, null: false
  DateTime :deadline, deadline_opts[14]
end

For verify_account feature:
create_table(:account_verification_keys) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  String :key, null: false
  DateTime :requested_at, null: false, default: Sequel::CURRENT_TIMESTAMP
  DateTime :email_last_sent, null: false, default: Sequel::CURRENT_TIMESTAMP
end

For lockout feature:
create_table(:account_login_failures) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  Integer :number, null: false, default: 1
end

create_table(:account_lockouts) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  String :key, null: false
  DateTime :deadline, deadline_opts[1]
  DateTime :email_last_sent
end

For active_sessions feature:
create_table(:account_active_session_keys) do
  foreign_key :account_id, :accounts, type: :Bignum
  String :session_id
  Time :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
  Time :last_use, null: false, default: Sequel::CURRENT_TIMESTAMP
  primary_key [:account_id, :session_id]
end

Database-Specific Setup

PostgreSQL Setup

# Create users
createuser -U postgres ${DATABASE_NAME}
createuser -U postgres ${DATABASE_NAME}_password

# Create database
createdb -U postgres -O ${DATABASE_NAME} ${DATABASE_NAME}

# Load citext extension for case-insensitive emails
psql -U postgres -c "CREATE EXTENSION citext" ${DATABASE_NAME}

# Optional: For PostgreSQL 15+, grant schema permissions
psql -U postgres -c "GRANT CREATE ON SCHEMA public TO ${DATABASE_NAME}_password" ${DATABASE_NAME}

SQLite Setup

SQLite requires no special setup - just ensure the database file exists and is writable. The schema works identically, though without the
citext extension for case-insensitive emails.

Security Considerations

- Separate Password User: For maximum security, use separate database accounts for application logic vs password hash access
- Database Functions: PostgreSQL, MySQL, and SQL Server support database functions that prevent the application user from directly reading
password hashes
- Email Validation: PostgreSQL's citext extension provides case-insensitive email handling with constraints

Your current setup appears to be using SQLite based on the auth.db file, which simplifies deployment but you'll want to ensure proper file
permissions and backup strategies.

## Updated Schema Files

### PostgreSQL Schema (`example_db_schema-pg.sql`)
- **Full-featured schema** with all Rodauth tables for future expansion
- **citext extension** for case-insensitive email handling
- **Partial indexes** for efficient email uniqueness (active accounts only)
- **Advanced features**: audit logging, WebAuthn, MFA, database functions
- **Best for**: Production PostgreSQL deployments

### SQLite Essential Schema (`essential_db_schema-sqlite3.sql`)
- **Minimal schema** focused on your 13 enabled features only
- **COLLATE NOCASE** for case-insensitive emails in SQLite
- **Optimized indexes** for performance
- **Maintenance triggers** for automatic cleanup
- **Best for**: Current auth app and development

## Key Differences

| Feature | PostgreSQL | SQLite |
|---------|------------|--------|
| Case-insensitive emails | `citext` extension | `COLLATE NOCASE` |
| Foreign key column naming | `id` (Rodauth standard) | `id` for most, `account_id` for sessions |
| Partial indexes | Supported | Not supported |
| JSON data type | `JSONB` | `TEXT` |
| Database functions | PL/pgSQL functions | Triggers only |

## Migration Path

1. **Current**: Use essential SQLite schema for auth app
2. **Future**: Migrate to PostgreSQL schema when scaling
3. **Data migration**: Use Sequel migrations for smooth transition

## Security Notes

- **PostgreSQL**: Supports separate database users for password hash isolation
- **SQLite**: Single database file - ensure proper file permissions (600)
- **Both**: Password hashes stored in separate table following Rodauth security model
