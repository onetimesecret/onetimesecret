# Database-Specific SQL Schemas

Database-specific SQL loaded by Sequel migrations (`001_initial.rb`, `002_extras.rb`).

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
- Views (complex JOINs/aggregations)
- Functions (PostgreSQL convenience operations)
- Triggers (automatic behaviors)
- Indexes (performance)
- Comments (self-documenting schema)

Raw SQL is clearer, more maintainable, and more powerful for database-specific features than Sequel DSLs.

## Loading Mechanism

```ruby
case database_type
when :postgres
  run File.read('schemas/postgres/002_extras.sql')
when :sqlite
  run File.read('schemas/sqlite/002_extras.sql')
end
```

## What's Created

See file headers and inline comments in:
- `postgres/002_extras.sql` - Views, functions, triggers, indexes
- `sqlite/002_extras.sql` - Views, triggers, indexes

PostgreSQL includes `COMMENT` statements on all objects. SQLite omits functions (not supported).

**Note:** `001_initial.sql` files are reference exports of Sequel-generated schema, not executed by migrations.
