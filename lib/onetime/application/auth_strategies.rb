# lib/onetime/application/auth_strategies.rb
#
# Centralized authentication strategies for Onetime applications.
# All applications (Web Core, V2 API, etc.) use these shared strategy classes.
#
# Keep this code in sync with:
# @see docs/architecture/authentication.md#authstrategies
#
# All dependent modules and references: `rg -t ruby -t markdown authstrategies`

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
          return nil if identity_id.to_s.empty?

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
            user_agent: env['HTTP_USER_AGENT'],
          }.merge(additional)
        end
      end

      # Registers core Onetime authentication strategies with Otto
      #
      # Registers session-based strategies (noauth, authenticated, colonelsonly).
      # For BasicAuth, call register_basic_auth(otto) separately.
      #
      # @param otto [Otto] Otto router instance
      def register_essential(otto)
        raise NotImplementedError, 'Please implement this method'
      end

      # Registers HTTP Basic Authentication strategy (opt-in)
      #
      # Only call this for apps that need API key authentication.
      # Reduces attack surface by not exposing Basic auth on all apps.
      #
      # @param otto [Otto] Otto router instance
      def register_basic_auth(otto)
        otto.add_auth_strategy('basicauth', BasicAuthStrategy.new)
      end

      # Public strategy - allows all requests, loads customer from session if available
      #
      # Routes: auth=noauth
      # Access: Everyone (including authenticated)
      # User: Customer.anonymous or authenticated Customer
      class NoAuthStrategy < Otto::Security::AuthStrategy
        @auth_method_name = 'noauth'

        def authenticate(env, _requirement)
          session = env['rack.session']

          # Load customer from session or use anonymous
          cust = load_customer_from_session(session) || Onetime::Customer.anonymous

          OT.ld "[onetime_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.objid})"

          success(
            session: session,
            user: cust,
            auth_method: 'noauth',
            metadata: build_metadata(env),
          )
        end

        include Helpers
      end

      # Base strategy for authenticated routes
      #
      # Provides common authentication logic for session-based auth.
      # Subclasses can override `additional_checks` for role/permission validation.
      class BaseSessionAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        @auth_method_name = nil

        def authenticate(env, _requirement)
          session = env['rack.session']
          return failure('[SESSION_MISSING] No session available') unless session

          # Check if authentication is enabled
          unless authentication_enabled?
            return failure('[AUTH_DISABLED] Authentication is disabled')
          end

          # Check if session is authenticated
          unless session['authenticated'] == true
            return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated')
          end

          identity_id = session['identity_id']
          if identity_id.to_s.empty?
            return failure('[IDENTITY_MISSING] No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.load(identity_id)
          return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

          # Perform additional checks (role, permissions, etc.)
          check_result = additional_checks(cust, env)
          return check_result if check_result.is_a?(Otto::Security::Authentication::FailureResult)

          log_success(cust)

          success(
            session: session,
            user: cust,
            auth_method: auth_method_name,
            metadata: build_metadata(env, additional_metadata(cust)),
          )
        end

        protected

        # Override in subclasses to add role/permission checks
        #
        # @param cust [Onetime::Customer] Authenticated customer
        # @param env [Hash] Rack environment
        # @return [Otto::Security::Authentication::FailureResult, nil] Failure if check fails, nil if passes
        def additional_checks(_cust, _env)
          nil
        end

        # Override in subclasses to customize auth method name
        #
        # @return [String] Auth method name for StrategyResult
        def auth_method_name
          @auth_method_name
        end

        # Override in subclasses to add metadata
        #
        # @param cust [Onetime::Customer] Authenticated customer
        # @return [Hash] Additional metadata for StrategyResult
        def additional_metadata(_cust)
          {}
        end

        # Override in subclasses to customize success logging
        #
        # @param cust [Onetime::Customer] Authenticated customer
        def log_success(cust)
          OT.ld "[onetime_authenticated] Authenticated '#{cust.objid}'"
        end

        private

        def authentication_enabled?
          settings = OT.conf.dig('site', 'authentication')
          return false unless settings

          settings['enabled'] == true
        end
      end

      # Authenticated strategy - requires valid session with authenticated customer
      #
      # Routes: auth=authenticated
      # Access: Authenticated users only
      # User: Authenticated Customer
      class SessionAuthStrategy < BaseSessionAuthStrategy
        @auth_method_name = 'sessionauth'
      end

      # Colonel strategy - requires authenticated user with colonel role
      #
      # Routes: auth=colonelsonly
      # Access: Users with colonel role only
      # User: Authenticated Customer with :colonel role
      class ColonelStrategy < BaseSessionAuthStrategy
        @auth_method_name = 'colonel'

        protected

        def additional_checks(cust, _env)
          return failure('[ROLE_COLONEL_REQUIRED] Colonel role required') unless cust.role?(:colonel)

          nil
        end

        def additional_metadata(_cust)
          { role: 'colonel' }
        end

        def log_success(cust)
          OT.ld "[onetime_colonel] Colonel access granted '#{cust.objid}'"
        end
      end

      # Basic auth strategy - HTTP Basic Authentication
      #
      # Routes: auth=basicauth
      # Access: Valid API credentials via Authorization header
      # User: Customer associated with API credentials
      #
      # Security: Uses constant-time comparison for both username and API key
      # to prevent timing attacks that could enumerate valid usernames.
      class BasicAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        @auth_method_name = 'basicauth'

        def authenticate(env, _requirement)
          # Extract credentials from Authorization header
          auth_header = env['HTTP_AUTHORIZATION']
          return failure('[AUTH_HEADER_MISSING] No authorization header') unless auth_header

          # Parse Basic auth
          unless auth_header.start_with?('Basic ')
            return failure('[AUTH_TYPE_INVALID] Invalid authorization type')
          end

          # Decode credentials
          encoded          = auth_header.sub('Basic ', '')
          decoded          = Base64.decode64(encoded)
          username, apikey = decoded.split(':', 2)

          return failure('[CREDENTIALS_FORMAT_INVALID] Invalid credentials format') unless username && apikey

          # Load customer by custid (may be nil)
          cust = Onetime::Customer.load(username)

          # Always validate API key to prevent timing attacks
          # If customer doesn't exist, validate against dummy value
          dummy_hash = Digest::SHA256.hexdigest("dummy:#{username}")
          apikey_to_check = apikey
          valid_apikey = if cust
                           cust.valid_apikey?(apikey_to_check)
                         else
                           # Perform same constant-time comparison with dummy value
                           # to prevent username enumeration via timing
                           Rack::Utils.secure_compare(dummy_hash, Digest::SHA256.hexdigest(apikey_to_check))
                           false  # Always fail for non-existent users
                         end

          unless valid_apikey
            return failure('[CREDENTIALS_INVALID] Invalid credentials')
          end

          OT.ld "[onetime_basic_auth] Authenticated '#{cust.objid}' via API key"

          success(
            session: {},  # No session for Basic auth (stateless)
            user: cust,
            auth_method: 'basic_auth',
            metadata: build_metadata(env, { auth_type: 'basic' }),
          )
        end
      end
    end
  end
end
