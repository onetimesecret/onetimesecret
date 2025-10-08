# lib/onetime/application/auth_strategies.rb
#
# Otto authentication strategies for V2 API endpoints.
# These strategies handle the various authentication methods used by V2 controllers.

module Onetime
  module Application
    module AuthStrategies
      extend self

      # Shared helper methods for authentication strategies
      module Helpers
        # Loads customer from session if authenticated
        #
        # @param session [Hash] Rack session
        # @return [Onetime::Customer, nil] Customer if found, nil otherwise
        def load_customer_from_session(session)
          return nil unless session
          return nil unless session['authenticated'] == true

          identity_id = session['identity_id']
          return nil unless identity_id.to_s.length > 0

          Onetime::Customer.load(identity_id)
        rescue StandardError => ex
          OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
          nil
        end

        # Builds standard metadata hash from env
        #
        # @param env [Hash] Rack environment
        # @param additional [Hash] Additional metadata to merge
        # @return [Hash] Metadata hash
        def build_metadata(env, additional = {})
          {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT']
          }.merge(additional)
        end
      end

      def register_all(otto)
        otto.enable_authentication!

        # HTTP Basic Auth with API token (for programmatic API access)
        otto.add_auth_strategy('basic', OnetimeBasicStrategy.new)

        # Identity-aware strategy (uses IdentityResolution middleware)
        otto.add_auth_strategy('advanced', OnetimeAdvancedStrategy.new)

        # V2 API authenticated routes - requires valid session OR basic auth
        # Used by: /api/v2/account, /api/v2/domains, /api/v2/receipt, /api/v2/private
        otto.add_auth_strategy('onetime_api', OnetimeApiStrategy.new)

        # V2 API optional auth - allows anonymous OR authenticated
        # Used by: /api/v2/secret (public secret operations)
        otto.add_auth_strategy('onetime_optional', OnetimeOptionalStrategy.new)

        # V2 API colonel routes - requires colonel role
        # Used by: /api/v2/colonel
        otto.add_auth_strategy('onetime_colonel', OnetimeColonelStrategy.new)

        # Fallback when authentication is disabled
        otto.add_auth_strategy('off', OnetimeDisabledStrategy.new)
      end

      # Basic authentication with API token
      class OnetimeBasicStrategy < Otto::Security::AuthStrategy
        def authenticate(env, _requirement)
          auth = Rack::Auth::Basic::Request.new(env)

          if auth.provided? && auth.basic?
            custid, apitoken = auth.credentials
            return failure('Invalid credentials format') if custid.to_s.empty? || apitoken.to_s.empty?

            OT.ld "[app] Basic attempt for '#{custid}' via #{env['REMOTE_ADDR']}"
            cust = Onetime::Customer.load(custid)
            return failure('Customer not found') if cust.nil?

            if cust.apitoken?(apitoken)
              OT.ld "[app] Basic authenticated '#{custid}'"
              return success(
                session: env['rack.session'] || {},
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
              OT.ld "[app] Advanced authenticated '#{identity.id}' via #{source}"
              return success(
                session: env['rack.session'] || {},
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

      # V2 API authenticated strategy - requires session OR basic auth
      # Combines session-based and API token authentication
      class OnetimeApiStrategy < Otto::Security::AuthStrategy
        include Helpers

        def authenticate(env, _requirement)
          session = env['rack.session']

          # Try session authentication first
          cust = load_customer_from_session(session)
          if cust
            OT.ld "[app] API session authenticated '#{cust.custid}'"
            return success(
              session: session,
              user: cust,
              auth_method: 'session',
              metadata: build_metadata(env)
            )
          end

          # Try HTTP Basic Auth with API token
          auth = Rack::Auth::Basic::Request.new(env)
          if auth.provided? && auth.basic?
            custid, apitoken = auth.credentials
            if custid.to_s.length > 0 && apitoken.to_s.length > 0
              cust = Onetime::Customer.load(custid)
              if cust && cust.apitoken?(apitoken)
                OT.ld "[app] API token authenticated '#{custid}'"
                return success(
                  session: session || {},
                  user: cust,
                  auth_method: 'basic',
                  metadata: build_metadata(env)
                )
              end
            end
          end

          failure('Authentication required')
        end
      end

      # V2 API optional strategy - allows anonymous OR authenticated
      # Same as PublicStrategy but for API routes
      class OnetimeOptionalStrategy < Otto::Security::AuthStrategy
        include Helpers

        def authenticate(env, _requirement)
          session = env['rack.session']

          # Try to load authenticated customer from session
          cust = load_customer_from_session(session)
          if cust
            OT.ld "[app] Optional authenticated '#{cust.custid}'"
            return success(
              session: session,
              user: cust,
              auth_method: 'session',
              metadata: build_metadata(env)
            )
          end

          # Fall back to anonymous
          OT.ld '[app] Optional anonymous access'
          success(
            session: session || {},
            user: Onetime::Customer.anonymous,
            auth_method: 'public',
            metadata: build_metadata(env)
          )
        end
      end

      # V2 API colonel strategy - requires colonel role
      class OnetimeColonelStrategy < Otto::Security::AuthStrategy
        include Helpers

        def authenticate(env, _requirement)
          session = env['rack.session']
          return failure('No session available') unless session

          # Load authenticated customer
          cust = load_customer_from_session(session)
          return failure('Not authenticated') unless cust

          # Check colonel role
          unless cust.role?(:colonel)
            return failure('Colonel role required')
          end

          OT.ld "[app] Colonel access granted '#{cust.custid}'"

          success(
            session: session,
            user: cust,
            auth_method: 'colonel',
            metadata: build_metadata(env, role: 'colonel')
          )
        end
      end

      # All authentication is disabled
      class OnetimeDisabledStrategy < Otto::Security::AuthStrategy
        def authenticate(env, _requirement)
          # Everyone is a pseudo-anonymous user
          OT.ld '[app] Disabled fallback anonymous access'
          success(
            session: env['rack.session'] || {},
            user: Onetime::Customer.anonymous,
            auth_method: 'anonymous',
          )
        end
      end
    end
  end
end
