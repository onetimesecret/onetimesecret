# lib/middleware/entitlement_test_mode.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # EntitlementTestMode Middleware
    #
    # Transfers colonel test mode session override to Thread.current for entitlement checks.
    # This allows colonels to test plan features without changing actual subscription data.
    #
    # ## Flow
    #
    # 1. Check session for :entitlement_test_planid
    # 2. If present, set Thread.current[:entitlement_test_planid]
    # 3. WithEntitlements#entitlements checks Thread.current first
    # 4. Clean up Thread.current after request
    #
    # ## Security
    #
    # - Session override set only by colonel-protected API endpoint
    # - Thread.current is request-scoped and cleaned up in ensure block
    # - Only affects entitlement checks, not actual billing/subscription data
    #
    # @see WithEntitlements#entitlements
    # @see ColonelAPI::Logic::Colonel::SetEntitlementTest
    class EntitlementTestMode
      def initialize(app)
        @app = app
      end

      def call(env)
        session = env['rack.session']

        # Copy session override to Thread.current for this request
        if session && session[:entitlement_test_planid]
          Thread.current[:entitlement_test_planid] = session[:entitlement_test_planid]
        end

        @app.call(env)
      ensure
        # Always clear Thread.current to avoid leaking to next request
        Thread.current[:entitlement_test_planid] = nil
      end
    end
  end
end
