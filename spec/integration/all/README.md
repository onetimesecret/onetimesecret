# `spec/integration/all/` — Database-Agnostic Integration Specs

## Contract

Specs in this directory are **database-agnostic**. They run against both SQLite
and PostgreSQL (via the `agnostic_on_pg` CI matrix rows), and they run against a
PostgreSQL schema that does **not** include the trigger-enabled suite setup.

**Do not assert on PostgreSQL-specific behavior here.** That includes:

- Database **triggers** on the Rodauth auth tables (see below)
- `citext` case-insensitive comparison semantics
- PG-only constraints, functions, or extension behavior

A spec that depends on any of those belongs in
`spec/integration/full/database_triggers/` (tagged `:full_auth_mode,
:postgres_database`), where `PostgresModeSuiteDatabase.setup!`
(`spec/support/postgres_mode_suite_database.rb`) provisions the trigger-enabled
schema.

## Why this boundary matters

The triggers defined in
`apps/web/auth/migrations/schemas/postgres/004_triggers_⬆.sql` fire **only** on
the trigger-enabled schema:

1. `update_accounts_updated_at` — BEFORE UPDATE on `accounts`, auto-bumps `updated_at`
2. `trigger_update_last_login_time` — AFTER INSERT on `account_authentication_audit_logs`, populates `account_activity_times`
3. `trigger_cleanup_expired_tokens_extended` — AFTER INSERT on `account_jwt_refresh_keys`, deletes expired tokens

If a trigger-dependent assertion is placed in this directory, it passes green
under SQLite and under plain PostgreSQL — because the trigger never fires — while
the behavior it claims to test is never exercised. That false negative is the
failure mode this contract exists to prevent.

## What lives here today

App-domain and infrastructure integration specs that touch only Familia/Valkey
(Redis) models (`Customer`, `Organization`), HTTP/render/boot layers, RabbitMQ
workers, and Puma fork lifecycle. None touch the Rodauth auth tables. Keep it
that way.
