# apps/web/auth/initializers/seed_dev_oauth_client.rb
#
# frozen_string_literal: true

require 'bcrypt'

module Auth
  module Initializers
    # Seed a development OAuth/OIDC SP client into the oauth_applications table.
    #
    # Runs only in development and test. The client_id "onetimesecret-sp-dev"
    # is reserved for local development — real production SP clients are
    # provisioned through a separate (manual or admin-tooled) path.
    #
    # Idempotent: looks up the row by client_id. If it already exists, the
    # drift-prone columns (scopes, grant_types) are reconciled to the current
    # desired values so an environment seeded before a config change self-heals
    # on the next boot; otherwise a fresh row is inserted. Safe to run on every
    # boot.
    #
    # The plaintext client secret lives in OAUTH_SP_DEV_CLIENT_SECRET. The
    # column stores its bcrypt hash (rodauth-oauth's `secret_hash` default,
    # see oauth_base.rb:442 → `password_hash` → `BCrypt::Password.create(..., cost: BCrypt::Engine::DEFAULT_COST)`).
    #
    # @see apps/web/auth/migrations/008_oauth_applications.rb
    # @see https://github.com/onetimesecret/onetimesecret/issues/3104
    class SeedDevOAuthClient < Onetime::Boot::Initializer
      @depends_on = [:rodauth_schema]
      @provides   = [:dev_oauth_client]
      @optional   = true

      DEV_CLIENT_ID = 'onetimesecret-sp-dev'

      # Columns most likely to drift when the IdP config changes in code. Kept
      # as constants so the insert and the reconcile-on-exists path share one
      # source of truth. offline_access is required for refresh tokens:
      # rodauth-oauth intersects granted scopes against this per-application
      # column, so omitting it strips offline_access even when the server
      # allow-list (oauth_application_scopes) permits it.
      DEV_CLIENT_SCOPES      = 'openid email profile offline_access'
      DEV_CLIENT_GRANT_TYPES = 'authorization_code refresh_token'

      # The redirect_uri stored on the seeded row MUST match the SP-side
      # provider's callback URL exactly (rodauth-oauth requires exact-match
      # validation in /authorize). The default below mirrors the formula
      # used by Features::OmniAuth.configure_local_idp_provider so that when
      # OAUTH_SP_DEV_ROUTE_NAME is overridden, both ends stay in lockstep.
      # Override the final URL directly via OAUTH_SP_DEV_REDIRECT_URI.
      def self.default_redirect_uri
        route_name = ENV.fetch('OAUTH_SP_DEV_ROUTE_NAME', 'local')
        "http://localhost:3000/auth/sso/#{route_name}/callback"
      end

      def should_skip?
        # Only relevant in full mode
        return true unless Onetime.auth_config.full_enabled?
        # Only seed when the IdP feature is on
        return true unless Onetime.auth_config.oauth_enabled?
        # Never seed in production/staging — the row name says "dev" and the
        # plaintext secret lives in an env var, which is not the trust posture
        # we want for production clients. Real prod clients are seeded out-of-band.
        return true unless Onetime.development? || Onetime.testing?

        # Need the plaintext secret to derive the bcrypt hash. Without it we
        # have nothing to insert — skip rather than raise; the IdP can still
        # serve external clients seeded by another path.
        secret = ENV.fetch('OAUTH_SP_DEV_CLIENT_SECRET', nil)
        if secret.nil? || secret.empty?
          Onetime.auth_logger.info '[SeedDevOAuthClient] OAUTH_SP_DEV_CLIENT_SECRET not set — skipping dev SP seed'
          return true
        end

        false
      end

      def execute(_context)
        secret = ENV.fetch('OAUTH_SP_DEV_CLIENT_SECRET')

        require 'auth/database'
        db           = Auth::Database.connection
        applications = db[:oauth_applications]

        # Reconcile an existing row instead of skipping it: a DB seeded before a
        # scope/grant_types change would otherwise silently keep the stale value
        # (e.g. missing offline_access → the per-application scope intersection
        # strips it and refresh-token issuance fails locally). update returns the
        # affected row count; a non-zero result means the row existed and is now
        # current, so we're done. Reconciling to identical values is harmless, so
        # concurrent boots converging here is fine.
        reconciled = applications
          .where(client_id: DEV_CLIENT_ID)
          .update(scopes: DEV_CLIENT_SCOPES, grant_types: DEV_CLIENT_GRANT_TYPES)
        if reconciled.positive?
          Onetime.auth_logger.debug "[SeedDevOAuthClient] #{DEV_CLIENT_ID} exists — reconciled scopes/grant_types"
          return
        end

        # The reconcile/insert pair above is NOT atomic; under concurrent boot
        # (two workers seeding at once) both can see zero reconciled rows and
        # fall through to insert. The unique index on client_id is the actual
        # safety net, so we treat the race-loser's UniqueConstraintViolation as
        # success.
        begin
          applications.insert(
            account_id: nil, # system-owned
            name: 'OneTimeSecret SP (development)',
            description: 'Local dev Service Provider — authenticates against this instance via OAuth/OIDC.',
            redirect_uri: ENV.fetch('OAUTH_SP_DEV_REDIRECT_URI', self.class.default_redirect_uri),
            client_id: DEV_CLIENT_ID,
            client_secret: BCrypt::Password.create(secret),
            scopes: DEV_CLIENT_SCOPES,
            subject_type: 'public',
            id_token_signed_response_alg: 'RS256',
            token_endpoint_auth_method: 'client_secret_basic',
            grant_types: DEV_CLIENT_GRANT_TYPES,
            response_types: 'code',
          )
          Onetime.auth_logger.info "[SeedDevOAuthClient] inserted dev SP client: #{DEV_CLIENT_ID}"
        rescue Sequel::UniqueConstraintViolation
          Onetime.auth_logger.debug "[SeedDevOAuthClient] #{DEV_CLIENT_ID} created concurrently — skipping"
        end
      end
    end
  end
end
