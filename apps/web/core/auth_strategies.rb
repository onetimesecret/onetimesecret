# frozen_string_literal: true

# Otto authentication strategies for Web Core (apps/web/core).
# These strategies replace the wrapper methods (publically, authenticated, colonels)
# with declarative route-based authentication.
#
# Usage in apps/web/core/app.rb:
#   Core::AuthStrategies.register_all(router)
#
# Usage in routes file:
#   GET /public   Controller#action auth=publicly
#   GET /private  Controller#action auth=authenticated
#   GET /admin    Controller#action auth=colonel

module Core
  module AuthStrategies
    extend self

    def register_all(otto)
      otto.enable_authentication!

      # Public routes - allows everyone (anonymous or authenticated)
      otto.add_auth_strategy('publicly', PublicStrategy.new)

      # Authenticated routes - requires valid session
      otto.add_auth_strategy('authenticated', AuthenticatedStrategy.new)

      # Colonel routes - requires colonel role
      otto.add_auth_strategy('colonel', ColonelStrategy.new)
    end

    # Public strategy - allows all requests, loads customer from session if available.
    # Replaces the `publically` wrapper method.
    class PublicStrategy < Otto::Security::AuthStrategy
      def authenticate(env, _requirement)
        session = env['rack.session']

        # Load customer from session or use anonymous
        cust = load_customer_from_session(session)

        OT.ld "[onetime_web_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.custid})"

        success(
          session: session,
          user: cust,
          auth_method: 'public',
          metadata: {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT']
          }
        )
      end

      private

      def load_customer_from_session(session)
        return Onetime::Customer.anonymous unless session

        # Check if authenticated
        return Onetime::Customer.anonymous unless session['authenticated'] == true

        identity_id = session['identity_id']
        return Onetime::Customer.anonymous unless identity_id.to_s.length > 0

        # Load customer
        cust = Onetime::Customer.load(identity_id)
        return Onetime::Customer.anonymous unless cust

        cust
      rescue StandardError => ex
        OT.le "[onetime_web_public] Failed to load customer: #{ex.message}"
        Onetime::Customer.anonymous
      end
    end

    # Authenticated strategy - requires valid session with authenticated customer.
    # Replaces the `authenticated` wrapper method.
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

        OT.ld "[onetime_web_authenticated] Authenticated '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT']
          }
        )
      end

      private

      def authentication_enabled?
        settings = OT.conf.dig('site', 'authentication')
        return false unless settings

        settings['enabled'] == true
      end
    end

    # Colonel strategy - requires authenticated user with colonel role.
    # Replaces the `colonels` wrapper method.
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

        OT.ld "[onetime_web_colonel] Colonel access granted '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'colonel',
          metadata: {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT'],
            role: 'colonel'
          }
        )
      end

      private

      def authentication_enabled?
        settings = OT.conf.dig('site', 'authentication')
        return false unless settings

        settings['enabled'] == true
      end
    end
  end
end
