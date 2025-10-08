# frozen_string_literal: true

# Otto authentication strategies for V2 API (apps/api/v2).
# Uses the same authentication strategies as Web Core.
#
# Usage in apps/api/v2/application.rb:
#   V2::AuthStrategies.register_all(router)
#
# Usage in routes file:
#   GET /account   Controller#action auth=authenticated
#   GET /secret    Controller#action auth=publicly
#   GET /colonel   Controller#action auth=colonel

module V2
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

    # Public strategy - allows all requests, loads customer from session if available
    class PublicStrategy < Otto::Security::AuthStrategy
      include Onetime::Application::AuthStrategies::Helpers

      def authenticate(env, _requirement)
        session = env['rack.session']

        # Load customer from session or use anonymous
        cust = load_customer_from_session(session) || Onetime::Customer.anonymous

        OT.ld "[v2_public] Access granted (#{cust.anonymous? ? 'anonymous' : cust.custid})"

        success(
          session: session,
          user: cust,
          auth_method: 'public',
          metadata: build_metadata(env)
        )
      end
    end

    # Authenticated strategy - requires valid session with authenticated customer
    class AuthenticatedStrategy < Otto::Security::AuthStrategy
      include Onetime::Application::AuthStrategies::Helpers

      def authenticate(env, _requirement)
        session = env['rack.session']
        return failure('No session available') unless session

        # Load authenticated customer
        cust = load_customer_from_session(session)
        return failure('Not authenticated') unless cust

        OT.ld "[v2_authenticated] Authenticated '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'session',
          metadata: build_metadata(env)
        )
      end
    end

    # Colonel strategy - requires authenticated user with colonel role
    class ColonelStrategy < Otto::Security::AuthStrategy
      include Onetime::Application::AuthStrategies::Helpers

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

        OT.ld "[v2_colonel] Colonel access granted '#{cust.custid}'"

        success(
          session: session,
          user: cust,
          auth_method: 'colonel',
          metadata: build_metadata(env, role: 'colonel')
        )
      end
    end
  end
end
