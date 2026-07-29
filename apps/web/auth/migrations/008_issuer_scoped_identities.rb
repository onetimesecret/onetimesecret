# apps/web/auth/migrations/008_issuer_scoped_identities.rb
#
# frozen_string_literal: true

# Issuer-scoped SSO identities (#3840 Phase 0 / #3838 item 5).
#
# WHY: account_identities was uniquely keyed on (provider, uid). `provider` is
# the strategy NAME ('oidc', 'entra') — identical across every tenant that uses
# that strategy via CustomDomain::SsoConfig. Two different IdPs (issuers) can
# each assert the same `sub` (uid). Under the old key the second IdP's callback
# matched the FIRST tenant's row → cross-tenant account takeover. Re-keying on
# (provider, issuer, uid) makes the two colliding identities distinct rows.
#
# BACKFILL POLICY (Approach A — platform grace + lazy upgrade):
# Existing rows CANNOT be given a real issuer — #3838 bars reconstructing it
# from logs, and it is not stored anywhere on the row. So EVERY pre-existing row
# is backfilled to the sentinel issuer '' (empty string, NEVER NULL — a NULL vs
# '' split would break the unique index). The read path (see lookup_identity
# in apps/web/auth/config/features/omniauth.rb) then handles the sentinel:
#   - PLATFORM callbacks fall back to the '' row and lazily upgrade its issuer
#     to the resolved value (self-heal).
#   - TENANT callbacks are issuer-exact ONLY and never touch the '' row — the
#     legacy fallback on the tenant path IS the item-5 takeover.
# The backfill is therefore unconditional '' and deliberately does NOT read
# ENV['OIDC_ISSUER']; issuer reconstruction happens at read time, not here.

Sequel.migration do
  up do
    # 1. Add the issuer column NOT NULL with the '' sentinel default. On every
    #    supported backend, ADD COLUMN ... DEFAULT '' backfills existing rows to
    #    '' in a single step (the universal sentinel required by Approach A).
    alter_table(:account_identities) do
      add_column :issuer, String, null: false, default: ''
    end

    # 2. Swap the uniqueness key (provider, uid) -> (provider, issuer, uid).
    #    006 created `unique [:provider, :uid]` as an UNNAMED table-level UNIQUE
    #    constraint (not a standalone index), so removal differs by backend.
    case database_type
    when :sqlite
      # SQLite cannot drop an inline UNIQUE constraint in place; Sequel emulates
      # by rebuilding the table. A fresh 006 has exactly one unique constraint
      # (the inline (provider, uid)), so dropping "the unique constraint" is
      # unambiguous. The rebuild preserves the account_id index.
      alter_table(:account_identities) do
        drop_constraint(nil, type: :unique)
      end
      # A prior `down` of THIS migration restores (provider, uid) as a STANDALONE
      # unique INDEX, not an inline constraint. drop_constraint above rebuilds the
      # table but cannot see that index — it re-creates it. Drop it idempotently
      # so an up->down->up cycle can't leave a stale (provider, uid) unique that
      # would silently defeat issuer-scoping (verified: without this, colliding
      # rows are rejected after a re-migration). Mirrors the postgres branch.
      run 'DROP INDEX IF EXISTS account_identities_provider_uid_index'
    when :postgres
      # Drop the (provider, uid) uniqueness idempotently. Migration 006 created
      # it as an unnamed table-level UNIQUE constraint, which PostgreSQL names
      # deterministically `<table>_<cols>_key`. IF EXISTS also tolerates the
      # shape a prior `down` of THIS migration leaves behind (a standalone unique
      # INDEX rather than a constraint), so up->down->up cycles in dev/CI don't
      # fail on a missing constraint.
      run 'ALTER TABLE account_identities DROP CONSTRAINT IF EXISTS account_identities_provider_uid_key'
      run 'DROP INDEX IF EXISTS account_identities_provider_uid_index'
    else
      # MySQL/MSSQL are NOT supported deployment targets — this project ships
      # only PostgreSQL and SQLite. This branch is best-effort and UNVERIFIED:
      # those backends name the 006 constraint by their own convention, which
      # may differ from the PostgreSQL-style name assumed here, so drop_constraint
      # can miss and abort the migration. If you add such a target, verify this
      # path (and the paired `down`) against its real constraint name first.
      alter_table(:account_identities) do
        drop_constraint(:account_identities_provider_uid_key, type: :unique)
      end
    end

    # CONCURRENTLY is intentionally not used: the migration runs in one
    # transaction (CONCURRENTLY is forbidden there) and SQLite has no such
    # option. account_identities holds SSO users only, so the brief lock is
    # negligible. Sequel names the index "<table>_<cols>_index" by convention,
    # which `down` drops by columns.
    # rubocop:disable Sequel/ConcurrentIndex
    alter_table(:account_identities) do
      add_index [:provider, :issuer, :uid], unique: true
    end
    # rubocop:enable Sequel/ConcurrentIndex
  end

  down do
    # Reverse: drop the composite unique, restore (provider, uid) uniqueness,
    # then drop the column. The composite index references :issuer, so it must be
    # dropped before the column.
    #
    # NOTE: uniqueness is restored as a standalone unique INDEX, not the original
    # unnamed table-level UNIQUE constraint from migration 006. For PostgreSQL and
    # SQLite the two are functionally interchangeable for Rodauth's uniqueness
    # check, and the paired `up` idempotently drops BOTH forms (inline constraint
    # and standalone index) on each backend, so an up->down->up cycle stays
    # consistent.
    #
    # A rollback WILL fail if production already holds two identities that share
    # (provider, uid) but differ by issuer — precisely the collisions this schema
    # was introduced to admit. That data cannot be collapsed back onto a unique
    # (provider, uid) key; reconcile such rows manually before rolling back.
    # rubocop:disable Sequel/ConcurrentIndex
    case database_type
    when :postgres
      run 'DROP INDEX IF EXISTS account_identities_provider_issuer_uid_index'
    else
      alter_table(:account_identities) do
        drop_index [:provider, :issuer, :uid]
      end
    end

    alter_table(:account_identities) do
      add_index [:provider, :uid], unique: true
    end
    # rubocop:enable Sequel/ConcurrentIndex

    alter_table(:account_identities) do
      drop_column :issuer
    end
  end
end
