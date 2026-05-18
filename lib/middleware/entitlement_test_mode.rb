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
    # ## Phase 2 Flow (reconciler-based)
    #
    # 1. Check session for :entitlement_test_grants_key and :entitlement_test_revokes_key
    # 2. If present, set Thread.current keys for the reconciler
    # 3. WithEntitlements#entitlements uses reconcile_with_session_overrides
    # 4. Clean up Thread.current after request
    #
    # ## Legacy Flow (planid-based, deprecated)
    #
    # 1. Check session for :entitlement_test_planid
    # 2. If present, set Thread.current[:entitlement_test_planid]
    # 3. WithEntitlements#entitlements calls test_plan_entitlements
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
        return @app.call(env) unless session

        # Phase 2: Reconciler-based test mode (session grants/revokes keys)
        if session[:entitlement_test_grants_key] || session[:entitlement_test_revokes_key]
          Thread.current[:entitlement_test_grants_key]  = session[:entitlement_test_grants_key]
          Thread.current[:entitlement_test_revokes_key] = session[:entitlement_test_revokes_key]
        end

        # Legacy: Planid-based test mode (fallback for transition)
        if session[:entitlement_test_planid]
          Thread.current[:entitlement_test_planid] = session[:entitlement_test_planid]
        end

        @app.call(env)
      ensure
        # Always clear Thread.current to avoid leaking to next request
        Thread.current[:entitlement_test_planid]      = nil
        Thread.current[:entitlement_test_grants_key]  = nil
        Thread.current[:entitlement_test_revokes_key] = nil
      end
    end
  end
end
