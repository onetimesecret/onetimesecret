# Database-Specific SQL Schemas

Database-specific SQL loaded by Sequel migrations.

## First-Time Setup

**PostgreSQL users:**

```bash
cd postgres
psql -U postgres -h localhost -f setup_auth_db.sql
```

See `postgres/README.md` for details.

## Architecture

**Why hybrid Sequel + SQL?**

Sequel handles cross-database table creation. Database-specific SQL provides:
- Indexes (performance optimization)
- Functions (PostgreSQL convenience operations)
- Triggers (automatic behaviors)
- Views (complex JOINs/aggregations)
- Comments (self-documenting schema)

Raw SQL is clearer, more maintainable, and more powerful for database-specific features than Sequel DSLs.

## Arrow Symbol Convention

- `⬆` (U+2B06) - Up migration (applies changes)
- `⬇` (U+2B07) - Down migration (rollback)

## Loading Mechanism

```ruby
case database_type
when :postgres
  run File.read('schemas/postgres/003_functions_⬆.sql')
when :sqlite
  run File.read('schemas/sqlite/003_functions_⬆.sql')
end
```

PostgreSQL includes `COMMENT` statements on all objects. SQLite has more inline triggers since it lacks stored functions.
