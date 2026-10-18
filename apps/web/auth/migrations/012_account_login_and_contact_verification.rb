# apps/web/auth/migrations/012_account_login_and_contact_verification.rb
#
# frozen_string_literal: true

# Phase 2 of SSO email-less accounts, step M012 "expand" (ADR-051,
# docs/specs/sso-email-less-accounts/account-model-design.md §3.1, §7).
#
# Separates three facts the `accounts` table has so far represented with one
# column and one status value:
#
#   login                   the opaque internal Rodauth login. Its value is the
#                           objid of the Customer reserved for the account, so
#                           `external_id` is a pure function of it. Never
#                           derived from a claim, never shown to a user, never
#                           accepted from a request, never written to a log.
#   email                   the optional contact address. UNCHANGED here: it
#                           stays NOT NULL and stays the Rodauth login column
#                           until M013/M014 and the N+1 binary ship.
#   email_verified_at       when mailbox control was established for the
#   email_verified_by       CURRENT email value, by which path (one of
#                           Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY),
#   email_verification_hold or why an IdP-asserted address was deliberately
#                           left unverified (Onetime::Customer::VERIFICATION_HOLDS).
#                           Mutually exclusive with email_verified_at.
#
# EXPAND ONLY. Every new column is nullable with no default, so the running
# binary (which does not know these columns) keeps inserting and reading rows
# exactly as before; its rows simply carry NULL `login`. The values are
# supplied afterwards by `bin/ots customers backfill-logins`
# (Auth::Operations::BackfillAccountLogins), which is resumable and
# idempotent, and by the N+1 binary on every INSERT. `login NOT NULL` is a
# later migration (M013) that refuses to run while any row still lacks one.
#
# The UNIQUE index on `login` is created now rather than at M013 on purpose:
# PostgreSQL and SQLite both treat NULLs as distinct in a unique index, so the
# NULL-login rows the old binary keeps writing are unaffected, while two rows
# can never be backfilled onto one Customer objid even if two operators run
# the backfill at once. `down` is non-destructive to every pre-existing
# column; the data it drops is re-derivable by re-running the backfill.
#
# No step here reads or writes Redis, fabricates an address, or touches
# `account_identities`.

Sequel.migration do
  up do
    alter_table(:accounts) do
      add_column :login, String, null: true
      add_column :email_verified_at, DateTime, null: true
      add_column :email_verified_by, String, null: true
      add_column :email_verification_hold, String, null: true
    end

    # CONCURRENTLY is not an option inside the migration transaction (and
    # SQLite has none); the column is all-NULL at this point so the index
    # build is trivial. Sequel names it accounts_login_index, which `down`
    # drops by column.
    alter_table(:accounts) do
      add_index :login, unique: true # rubocop:disable Sequel/ConcurrentIndex
    end
  end

  down do
    # Index first: SQLite's native DROP COLUMN refuses an indexed column, and
    # Sequel's table-rebuild fallback is avoided when the index is gone.
    alter_table(:accounts) do
      drop_index :login # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:accounts) do
      drop_column :email_verification_hold
      drop_column :email_verified_by
      drop_column :email_verified_at
      drop_column :login
    end
  end
end
