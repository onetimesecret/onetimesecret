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

    # Import shared helpers from application auth strategies
    include Onetime::Application::AuthStrategies::Helpers

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
      include Onetime::Application::AuthStrategies::Helpers

      def authenticate(env, _requirement)
        session = env['rack.session']

        # Load customer from session or use anonymous
        cust = load_customer_from_session(session) || Onetime::Customer.anonymous

        OT.ld "[onetime_web_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.custid})"

        success(
          session: session,
          user: cust,
          auth_method: 'public',
          metadata: build_metadata(env)
        )
      end
    end

    # Authenticated strategy - requires valid session with authenticated customer.
    # Replaces the `authenticated` wrapper method.
    class AuthenticatedStrategy < Otto::Security::AuthStrategy
      include Onetime::Application::AuthStrategies::Helpers

      def authenticate(env, _requirement)
        session = env['rack.session']
        return failure('No session available') unless session

        # Check if authentication is enabled
        unless authentication_enabled?
          return failure('Authentication is disabled')
        end

        # Load authenticated customer
        cust = load_customer_from_session(session)
        return failure('Not authenticated') unless cust

        OT.ld "[onetime_web_authenticated] Authenticated '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: build_metadata(env)
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
      include Onetime::Application::AuthStrategies::Helpers

      def authenticate(env, _requirement)
        session = env['rack.session']
        return failure('No session available') unless session

        # Check if authentication is enabled
        unless authentication_enabled?
          return failure('Authentication is disabled')
        end

        # Load authenticated customer
        cust = load_customer_from_session(session)
        return failure('Not authenticated') unless cust

        # Check colonel role
        unless cust.role?(:colonel)
          return failure('Colonel role required')
        end

        OT.ld "[onetime_web_colonel] Colonel access granted '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'colonel',
          metadata: build_metadata(env, role: 'colonel')
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
