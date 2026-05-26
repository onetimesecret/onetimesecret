# apps/web/auth/migrations/008_oauth_applications.rb
#
# frozen_string_literal: true

# Migration for rodauth-oauth (1.6.x) client registry.
# Used by rodauth-oauth features: :oauth_authorization_code_grant, :oauth_pkce,
# :oidc, :oauth_jwt, :oauth_jwt_jwks, :oauth_dynamic_client_registration.
#
# A row in `oauth_applications` represents a registered OAuth/OIDC client.
# Most OIDC and dynamic-client-registration columns are nullable so that
# manually-seeded clients only need core fields populated; the gem reads
# the optional columns when the corresponding feature is enabled.
#
# Token/secret hashing: by default the gem stores a bcrypt hash of
# `client_secret` in the same column it reads from. No separate hash column.
#
# Usage:
#   # Up
#   $ sequel -m apps/web/auth/migrations -M 8 $AUTH_DATABASE_URL_MIGRATIONS
#
#   # Down
#   $ sequel -m apps/web/auth/migrations -M 7 $AUTH_DATABASE_URL_MIGRATIONS
#
# @see https://github.com/onetimesecret/onetimesecret/issues/3104
# @see lib/generators/rodauth/oauth/templates/db/migrate/create_rodauth_oauth.rb (rodauth-oauth 1.6.4)

MIGRATION_ROOT = __dir__ unless defined?(MIGRATION_ROOT)

Sequel.migration do
  up do
    create_table(:oauth_applications) do
      primary_key :id, type: :Bignum

      # nullable: some applications are system-owned, not user-owned
      foreign_key :account_id, :accounts, null: true, type: :Bignum, on_delete: :cascade

      # Core client metadata
      String :name, null: false
      String :description, text: true, null: true
      String :homepage_url, null: true
      # redirect_uri may hold multiple newline-separated URIs
      String :redirect_uri, text: true, null: false
      String :client_id, null: false
      # client_secret stores a bcrypt hash by default (gem option)
      String :client_secret, null: false
      # space-separated scope list, e.g. "openid email profile"
      String :scopes, text: true, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      # OIDC (rodauth-oauth :oidc feature)
      String :subject_type, null: true, default: 'public'
      String :id_token_signed_response_alg, null: true, default: 'RS256'
      String :userinfo_signed_response_alg, null: true
      String :request_object_signing_alg, null: true

      # Dynamic Client Registration (RFC 7591/7592)
      # All nullable; the gem reads these when :oauth_dynamic_client_registration
      # is enabled. We ship manual seeding but keep the columns present.
      String :token_endpoint_auth_method, null: true, default: 'client_secret_basic'
      String :grant_types, text: true, null: true, default: 'authorization_code'
      String :response_types, text: true, null: true, default: 'code'
      String :client_uri, null: true
      String :logo_uri, null: true
      String :tos_uri, null: true
      String :policy_uri, null: true
      String :jwks_uri, null: true
      String :jwks, text: true, null: true  # JSON-serialized JWKS
      String :contacts, text: true, null: true  # comma-separated
      String :software_id, null: true
      String :software_version, null: true
      String :registration_access_token, null: true

      # Forward-compat: RP-initiated logout (oidc_rp_initiated_logout)
      String :post_logout_redirect_uris, text: true, null: true

      index :client_id, unique: true
      index :account_id
    end

    case database_type
    when :mysql, :mssql
      user = if database_type == :mysql
        get(Sequel.lit('current_user')).sub(/_password@/, '@')
      else
        get(Sequel.function(:DB_NAME))
      end
      run "GRANT SELECT, INSERT, UPDATE, DELETE ON oauth_applications TO #{user}"
    end
  end

  down do
    drop_table(:oauth_applications)
  end
end
