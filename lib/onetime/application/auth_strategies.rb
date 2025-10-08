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

        # Register Web Core strategies (same auth as Web app)
        # Public routes - allows everyone (anonymous or authenticated)
        otto.add_auth_strategy('publicly', PublicStrategy.new)

        # Authenticated routes - requires valid session
        otto.add_auth_strategy('authenticated', AuthenticatedStrategy.new)

        # Colonel routes - requires colonel role
        otto.add_auth_strategy('colonel', ColonelStrategy.new)

        # Legacy/Advanced strategies
        # HTTP Basic Auth with API token (for programmatic API access)
        otto.add_auth_strategy('basic', OnetimeBasicStrategy.new)

        # Identity-aware strategy (uses IdentityResolution middleware)
        otto.add_auth_strategy('advanced', OnetimeAdvancedStrategy.new)

        # Fallback when authentication is disabled
        otto.add_auth_strategy('off', OnetimeDisabledStrategy.new)
      end

      # Public strategy - allows all requests, loads customer from session if available
      # Same as Web Core PublicStrategy
      class PublicStrategy < Otto::Security::AuthStrategy
        include Helpers

        def authenticate(env, _requirement)
          session = env['rack.session']

          # Load customer from session or use anonymous
          cust = load_customer_from_session(session) || Onetime::Customer.anonymous

          OT.ld "[app_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.custid})"

          success(
            session: session,
            user: cust,
            auth_method: 'public',
            metadata: build_metadata(env)
          )
        end
      end

      # Authenticated strategy - requires valid session with authenticated customer
      # Same as Web Core AuthenticatedStrategy
      class AuthenticatedStrategy < Otto::Security::AuthStrategy
        include Helpers

        def authenticate(env, _requirement)
          session = env['rack.session']
          return failure('No session available') unless session

          # Load authenticated customer
          cust = load_customer_from_session(session)
          return failure('Not authenticated') unless cust

          OT.ld "[app_authenticated] Authenticated '#{cust.custid}'"

          success(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: build_metadata(env)
          )
        end
      end

      # Colonel strategy - requires authenticated user with colonel role
      # Same as Web Core ColonelStrategy
      class ColonelStrategy < Otto::Security::AuthStrategy
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

          OT.ld "[app_colonel] Colonel access granted '#{cust.custid}'"

          success(
            session: session,
            user: cust,
            auth_method: 'colonel',
            metadata: build_metadata(env, role: 'colonel')
          )
        end
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
