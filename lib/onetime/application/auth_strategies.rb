# lib/onetime/application/auth_strategies.rb
#
# Centralized authentication strategies for Onetime applications.
# All applications (Web Core, V2 API, etc.) use these shared strategy classes.

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

      # Registers all Onetime authentication strategies with Otto
      #
      # @param otto [Otto] Otto router instance
      def register_all(otto)
        otto.enable_authentication!

        # Public routes - allows everyone (anonymous or authenticated)
        otto.add_auth_strategy('publicly', PublicStrategy.new)

        # Authenticated routes - requires valid session
        otto.add_auth_strategy('authenticated', AuthenticatedStrategy.new)

        # Colonel routes - requires colonel role
        otto.add_auth_strategy('colonel', ColonelStrategy.new)
      end

      # Public strategy - allows all requests, loads customer from session if available
      #
      # Routes: auth=publicly
      # Access: Everyone (anonymous or authenticated)
      # User: Customer.anonymous or authenticated Customer
      class PublicStrategy < Otto::Security::AuthStrategy
        def authenticate(env, _requirement)
          session = env['rack.session']

          # Load customer from session or use anonymous
          cust = load_customer_from_session(session) || Onetime::Customer.anonymous

          OT.ld "[onetime_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.custid})"

          success(
            session: session,
            user: cust,
            auth_method: 'public',
            metadata: build_metadata(env)
          )
        end

        private

        include Helpers
      end

      # Authenticated strategy - requires valid session with authenticated customer
      #
      # Routes: auth=authenticated
      # Access: Authenticated users only
      # User: Authenticated Customer
      class AuthenticatedStrategy < Otto::Security::AuthStrategy
        def authenticate(env, _requirement)
          session = env['rack.session']
          return failure('No session available') unless session

          # Check if authentication is enabled
          unless authentication_enabled?
            return failure('Authentication is disabled')
          end

          # Check if session is authenticated
          unless session['authenticated'] == true
            return failure('Not authenticated')
          end

          identity_id = session['identity_id']
          unless identity_id.to_s.length > 0
            return failure('No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.load(identity_id)
          return failure('Customer not found') unless cust

          OT.ld "[onetime_authenticated] Authenticated '#{cust.custid}'"

          success(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: build_metadata(env)
          )
        end

        private

        include Helpers

        def authentication_enabled?
          settings = OT.conf.dig('site', 'authentication')
          return false unless settings

          settings['enabled'] == true
        end
      end

      # Colonel strategy - requires authenticated user with colonel role
      #
      # Routes: auth=colonel
      # Access: Users with colonel role only
      # User: Authenticated Customer with :colonel role
      class ColonelStrategy < Otto::Security::AuthStrategy
        def authenticate(env, _requirement)
          session = env['rack.session']
          return failure('No session available') unless session

          # Check if authentication is enabled
          unless authentication_enabled?
            return failure('Authentication is disabled')
          end

          # Check if session is authenticated
          unless session['authenticated'] == true
            return failure('Not authenticated')
          end

          identity_id = session['identity_id']
          unless identity_id.to_s.length > 0
            return failure('No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.load(identity_id)
          return failure('Customer not found') unless cust

          # Check colonel role
          unless cust.role?(:colonel)
            return failure('Colonel role required')
          end

          OT.ld "[onetime_colonel] Colonel access granted '#{cust.custid}'"

          success(
            session: session,
            user: cust,
            auth_method: 'colonel',
            metadata: build_metadata(env, role: 'colonel')
          )
        end

        private

        include Helpers

        def authentication_enabled?
          settings = OT.conf.dig('site', 'authentication')
          return false unless settings

          settings['enabled'] == true
        end
      end
    end
  end
end
