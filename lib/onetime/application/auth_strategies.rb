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

          external_id = session['external_id']
          return nil if external_id.to_s.empty?

          Onetime::Customer.find_by_extid(external_id)
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

      # Checks if authentication is enabled in configuration
      #
      # @return [Boolean] true if authentication is enabled
      def authentication_enabled?
        settings = OT.conf.dig('site', 'authentication')
        return false unless settings

        settings['enabled'] == true
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

          OT.ld "[noauth] Access granted (#{cust.anonymous? ? 'anonymous' : cust.objid})"

          success(
            session: session,
            user: cust.anonymous? ? nil : cust,  # Pass nil for anonymous users
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

          # Check if session is authenticated
          unless session['authenticated'] == true
            return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated')
          end

          external_id = session['external_id']
          if external_id.to_s.empty?
            return failure('[IDENTITY_MISSING] No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.find_by_extid(external_id)
          return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

          # Perform additional checks (role, permissions, etc.)
          check_result = additional_checks(cust, env)
          return check_result if check_result.is_a?(Otto::Security::Authentication::AuthFailure)

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
        # @return [Otto::Security::Authentication::AuthFailure, nil] Failure if check fails, nil if passes
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

          # Timing attack mitigation:
          # To prevent username enumeration via timing analysis, we ensure that
          # authentication takes the same amount of time whether the user exists or not.
          #
          # Strategy:
          # 1. Use a dummy customer with a real BCrypt hash when user doesn't exist
          # 2. Always perform BCrypt password comparison (expensive operation)
          # 3. Both paths execute identical cryptographic operations
          #
          # The dummy customer has a pre-computed BCrypt hash, so passphrase?()
          # performs the same ~280ms BCrypt comparison for both existing and
          # non-existing users, making timing analysis ineffective.
          target_cust = cust || Onetime::Customer.dummy

          # Always validate credentials using BCrypt (constant-time comparison)
          # Note: This uses passphrase? for API key authentication (API key stored as passphrase)
          valid_credentials = target_cust.passphrase?(apikey)

          # Only succeed if we have a real customer AND valid credentials
          if cust && valid_credentials
            OT.ld "[onetime_basic_auth] Authenticated '#{cust.objid}' via API key"

            success(
              session: {},  # No session for Basic auth (stateless)
              user: cust,
              auth_method: 'basic_auth',
              metadata: build_metadata(env, { auth_type: 'basic' }),
            )
          else
            # Return generic error for both cases:
            # 1. User doesn't exist (cust is nil)
            # 2. Invalid credentials (valid_credentials is false)
            # The timing is identical in both cases due to our mitigation strategy
            failure('[CREDENTIALS_INVALID] Invalid credentials')
          end
        end
      end
    end
  end
end
