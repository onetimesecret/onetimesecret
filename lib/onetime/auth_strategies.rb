# lib/onetime/auth_strategies.rb
#
# Otto authentication strategies for V2 API endpoints.
# These strategies handle the various authentication methods used by V2 controllers.

module V2
  module AuthStrategies
    extend self

    def register_all(otto)
      otto.enable_authentication!

      # Basic authentication with API token
      otto.add_auth_strategy('basic', OnetimeBasicStrategy.new)

      # Combined basic + session authentication (most V2 endpoints)
      otto.add_auth_strategy('advanced', OnetimeAdvancedStrategy.new)

      # Optional authentication (non authenticated only)
      otto.add_auth_strategy('off', OnetimeDisabledStrategy.new)

    end

    # Basic authentication with API token
    class OnetimeBasicStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        auth = Rack::Auth::Basic::Request.new(env)

        if auth.provided? && auth.basic?
          custid, apitoken = auth.credentials
          return failure('Invalid credentials format') if custid.to_s.empty? || apitoken.to_s.empty?

          OT.ld "[onetime_basic] Attempt for '#{custid}' via #{env['REMOTE_ADDR']}"
          cust = Onetime::Customer.load(custid)
          return failure('Customer not found') if cust.nil?

          if cust.apitoken?(apitoken)
            OT.ld "[onetime_basic] Authenticated '#{custid}'"
            return success(
              session: env['onetime.session'] || {},
              user: cust,
              auth_method: 'basic',
            )
          end
        end

        failure('Invalid API credentials')
      end
    end

    # Combined basic + session authentication (identity-aware)
    class OnetimeAdvancedStrategy < Otto::Security::AuthStrategy
      def authenticate(env, requirement)
        # Use pre-resolved identity from IdentityResolution middleware
        # OR?
        # Try identity resolution first (covers both Rodauth and Redis sessions)
        identity = env['identity.resolved']

        if identity && env['identity.authenticated']
          source = env['identity.source']

          if %w[advanced basic].include?(source)
            OT.ld "[onetime_combined] Authenticated '#{identity.id}' via #{source}"
            return success(
              session: env['onetime.session'] || {},
              user: identity.customer || identity,
              auth_method: source,
              metadata: env['identity.metadata'],
            )
          end
        end

        # No Fallback.

        failure('No valid authentication found')
      end
    end

    # All authentication is disabled
    class OnetimeDisabledStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        # Everyone is a pseudo-anonymous user
        OT.ld '[onetime_optional] Fallback anonymous access'
        success(
          session: env['onetime.session'] || {},
          user: Onetime::Customer.anonymous,
          auth_method: 'anonymous',
        )
      end
    end
  end
end
