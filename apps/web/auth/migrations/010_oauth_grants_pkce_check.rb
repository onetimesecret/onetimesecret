# apps/web/auth/migrations/010_oauth_grants_pkce_check.rb
#
# frozen_string_literal: true

# Database-level guard rejecting PKCE `plain` challenges on oauth_grants.
#
# rodauth-oauth 1.6.4 rejects `plain` at /authorize (oauth_pkce.rb:64) but
# still accepts `plain` at /token redemption (oauth_pkce.rb:75-77). If any
# other code path were to insert an oauth_grants row with
# code_challenge_method='plain', the gem would redeem it. This CHECK
# constraint makes the data layer the source of truth for the policy:
# only S256 (or NULL, for non-PKCE flows) is allowed.
#
# Issue: https://github.com/onetimesecret/onetimesecret/issues/3232
#
# Usage:
#   # Up
#   $ sequel -m apps/web/auth/migrations -M 10 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 9 $AUTH_DATABASE_URL_MIGRATIONS

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    alter_table(:oauth_grants) do
      # Sequel's add_constraint generates a portable CHECK clause on both
      # SQLite (via table recreate when needed) and PostgreSQL. NULL is
      # permitted so non-PKCE auth-code flows (no challenge) still insert.
      add_constraint(
        :oauth_grants_pkce_s256_only,
        Sequel.|(
          { code_challenge_method: nil },
          { code_challenge_method: 'S256' },
        ),
      )
    end
  end

  down do
    alter_table(:oauth_grants) do
      drop_constraint(:oauth_grants_pkce_s256_only)
    end
  end
end
