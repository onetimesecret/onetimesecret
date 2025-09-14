# apps/api/v2/auth_strategies.rb
#
# Otto authentication strategies for V2 API endpoints.
# These strategies handle the various authentication methods used by V2 controllers.

module V2
  module AuthStrategies
    extend self

    def register_all(otto)
      otto.enable_authentication!

      # Basic authentication with API token
      otto.add_auth_strategy('v2_basic', V2BasicStrategy.new)

      # Session-based authentication
      otto.add_auth_strategy('v2_session', V2SessionStrategy.new)

      # Combined basic + session authentication (most V2 endpoints)
      otto.add_auth_strategy('v2_api', V2CombinedStrategy.new)

      # Optional authentication (allows anonymous)
      otto.add_auth_strategy('v2_optional', V2OptionalStrategy.new)

      # Colonel/admin authentication
      otto.add_auth_strategy('v2_colonel', V2ColonelStrategy.new)
    end

    # Basic authentication with API token
    class V2BasicStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        auth = Rack::Auth::Basic::Request.new(env)

        if auth.provided? && auth.basic?
          custid, apitoken = auth.credentials
          return failure('Invalid credentials format') if custid.to_s.empty? || apitoken.to_s.empty?

          OT.ld "[v2_basic] Attempt for '#{custid}' via #{env['REMOTE_ADDR']}"
          cust = V2::Customer.load(custid)
          return failure('Customer not found') if cust.nil?

          if cust.apitoken?(apitoken)
            OT.ld "[v2_basic] Authenticated '#{custid}'"
            return success(
              session: env['onetime.session'] || {},
              user: cust,
              auth_method: 'basic'
            )
          end
        end

        failure('Invalid API credentials')
      end
    end

    # Session-based authentication (uses identity resolution)
    class V2SessionStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        # Use pre-resolved identity from IdentityResolution middleware
        identity = env['identity.resolved']

        if identity && env['identity.authenticated']
          source = env['identity.source']

          if %w[rodauth redis].include?(source)
            OT.ld "[v2_session] Authenticated '#{identity.id}' via #{source}"
            return success(
              session: env['rack.session'] || {},
              user: identity.customer || identity, # RodauthUser has .customer, RedisUser is the customer
              auth_method: source,
              metadata: env['identity.metadata']
            )
          end
        end

        failure('Invalid session')
      end
    end

    # Combined basic + session authentication (identity-aware)
    class V2CombinedStrategy < Otto::Security::AuthStrategy
      def authenticate(env, requirement)
        # Try identity resolution first (covers both Rodauth and Redis sessions)
        identity = env['identity.resolved']

        if identity && env['identity.authenticated']
          source = env['identity.source']

          if %w[rodauth redis].include?(source)
            OT.ld "[v2_combined] Authenticated '#{identity.id}' via #{source}"
            return success(
              session: env['rack.session'] || {},
              user: identity.customer || identity,
              auth_method: source,
              metadata: env['identity.metadata']
            )
          end
        end

        # Fall back to basic auth for API access
        basic_strategy = V2BasicStrategy.new
        if result = basic_strategy.authenticate(env, requirement)
          return result if result
        end

        failure('No valid authentication found')
      end
    end

    # Optional authentication (allows anonymous)
    class V2OptionalStrategy < Otto::Security::AuthStrategy
      def authenticate(env, requirement)
        # Check identity resolution first
        identity = env['identity.resolved']

        if identity
          if env['identity.authenticated'] && %w[rodauth redis].include?(env['identity.source'])
            # Authenticated user
            source = env['identity.source']
            OT.ld "[v2_optional] Authenticated '#{identity.id}' via #{source}"
            return success(
              session: env['rack.session'] || {},
              user: identity.customer || identity,
              auth_method: source,
              metadata: env['identity.metadata']
            )
          elsif env['identity.source'] == 'anonymous'
            # Anonymous user from identity resolution
            OT.ld "[v2_optional] Anonymous access via #{env['REMOTE_ADDR']}"
            return success(
              session: env['rack.session'] || {},
              user: V2::Customer.anonymous,
              auth_method: 'anonymous'
            )
          end
        end

        # Fall back to basic auth
        basic_strategy = V2BasicStrategy.new
        if result = basic_strategy.authenticate(env, requirement)
          return result if result
        end

        # Default to anonymous
        OT.ld "[v2_optional] Fallback anonymous access"
        success(
          session: env['rack.session'] || {},
          user: V2::Customer.anonymous,
          auth_method: 'anonymous'
        )
      end
    end

    # Colonel/admin authentication (identity-aware)
    class V2ColonelStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        # Use pre-resolved identity from IdentityResolution middleware
        identity = env['identity.resolved']

        if identity && env['identity.authenticated']
          customer = identity.customer || identity
          source = env['identity.source']

          # Check if customer has colonel privileges
          if customer.respond_to?(:colonel?) && customer.colonel?
            OT.ld "[v2_colonel] Colonel authenticated '#{customer.custid}' via #{source}"
            return success(
              session: env['rack.session'] || {},
              user: customer,
              auth_method: 'colonel',
              metadata: env['identity.metadata']
            )
          end
        end

        OT.ld "[v2_colonel] Access denied - colonel privileges required"
        failure('Colonel privileges required')
      end
    end
  end
end
