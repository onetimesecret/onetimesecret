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
# '' split would break the unique index). The read path (see
# config/features/omniauth.rb#lookup_identity) then handles the sentinel:
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
      # by rebuilding the table. There is exactly one unique constraint on this
      # table, so dropping "the unique constraint" is unambiguous. The rebuild
      # preserves the account_id index.
      alter_table(:account_identities) do
        drop_constraint(nil, type: :unique)
      end
    else
      # PostgreSQL/MySQL/MSSQL: the constraint from `unique [:provider, :uid]`
      # is named deterministically by Sequel as "<table>_<cols>_key".
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
    # Reverse exactly: drop the composite unique, restore (provider, uid)
    # uniqueness, then drop the column. The composite index references :issuer,
    # so it must be dropped before the column.
    # rubocop:disable Sequel/ConcurrentIndex
    alter_table(:account_identities) do
      drop_index [:provider, :issuer, :uid]
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
