# apps/web/auth/migrations/009_oauth_grants.rb
#
# frozen_string_literal: true

# Migration for rodauth-oauth (1.6.x) grant storage.
# Single table that holds auth codes, access tokens, refresh tokens, PKCE
# state, OIDC nonce/claims, and revocation state for the rodauth-oauth
# features: :oauth_authorization_code_grant, :oauth_pkce, :oidc.
#
# Lifecycle of a row:
#   1. `/authorize` populates `code` (and PKCE/OIDC columns)
#   2. `/token` clears `code` and populates `token` and/or `refresh_token`
#   3. revocation sets `revoked_at`
#
# Token hashing: by default the gem stores bcrypt hashes of `token` and
# `refresh_token` in the same columns it reads from. No separate hash columns.
#
# Usage:
#   # Up
#   $ sequel -m apps/web/auth/migrations -M 9 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 8 $AUTH_DATABASE_URL_MIGRATIONS
#
# @see https://github.com/onetimesecret/onetimesecret/issues/3104
# @see lib/generators/rodauth/oauth/templates/db/migrate/create_rodauth_oauth.rb (rodauth-oauth 1.6.4)

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    create_table(:oauth_grants) do
      primary_key :id, type: :Bignum

      foreign_key :account_id, :accounts, null: false, type: :Bignum, on_delete: :cascade
      foreign_key :oauth_application_id, :oauth_applications, null: false, type: :Bignum, on_delete: :cascade

      # Populated for some flows (e.g. JWT bearer); nullable for standard auth-code flow.
      String :type, null: true

      # Auth code: set at /authorize, cleared at /token
      String :code, null: true

      # bcrypt hashes of the bearer/refresh tokens (default hashing behavior)
      String :token, null: true
      String :refresh_token, null: true

      # NOTE: `expires_in` is the gem's column name but it stores an absolute
      # timestamp (the moment the grant expires), NOT a duration. Kept as-is
      # to match the gem's expectations; do not rename.
      DateTime :expires_in, null: false

      String :redirect_uri, text: true, null: true
      DateTime :revoked_at, null: true
      String :scopes, text: true, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      String :access_type, null: true, default: 'offline'

      # PKCE (rodauth-oauth :oauth_pkce feature)
      String :code_challenge, null: true
      String :code_challenge_method, null: true

      # OIDC (rodauth-oauth :oidc feature)
      String :nonce, null: true
      String :acr, null: true
      String :claims_locales, null: true
      String :claims, text: true, null: true  # JSON-encoded requested claims

      index [:oauth_application_id, :code], unique: true
      index :token, unique: true
      index :refresh_token, unique: true
      index :account_id
    end

    case database_type
    when :mysql, :mssql
      user = if database_type == :mysql
        get(Sequel.lit('current_user')).sub(/_password@/, '@')
      else
        get(Sequel.function(:DB_NAME))
      end
      run "GRANT SELECT, INSERT, UPDATE, DELETE ON oauth_grants TO #{user}"
    end
  end

  down do
    drop_table(:oauth_grants)
  end
end
