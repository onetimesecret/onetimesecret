# Test Fixtures for Auth Trigger Validator

This directory contains intentionally buggy SQL files used to test `AuthTriggerValidator`.

## Purpose

These fixtures reproduce the bug fixed in commit d72db567e, where triggers referenced non-existent column `account_id` in the `account_activity_times` table. The actual table uses `id` as the column name (Rodauth standard for one-to-one relationships).

## Files

- `sqlite/002_extras.sql` - Buggy SQLite trigger syntax
- `postgres/002_extras.sql` - Buggy PostgreSQL function/trigger syntax

## The Bug

Migration `001_initial.rb` creates the table with correct column name:
```ruby
create_table(:account_activity_times) do
  foreign_key :id, :accounts, primary_key: true, type: :Bignum
  DateTime :last_activity_at, null: false
  DateTime :last_login_at, null: false
end
```

But the buggy triggers (in these fixtures) reference wrong column:
```sql
INSERT INTO account_activity_times (account_id, ...)  -- Wrong!
VALUES (NEW.account_id, ...)
```

Should be:
```sql
INSERT INTO account_activity_times (id, ...)  -- Correct!
VALUES (NEW.account_id, ...)
```

Note that `NEW.account_id` is correct (reading from source table `account_authentication_audit_logs`), but the destination column in `account_activity_times` is named `id`, not `account_id`.

## Usage

See `spec/support/auth_trigger_validator_spec.rb` for usage examples.

## DO NOT USE IN PRODUCTION

These files are for testing only and will cause runtime errors if used in actual migrations.
