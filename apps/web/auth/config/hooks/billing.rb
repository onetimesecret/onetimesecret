# apps/web/auth/config/hooks/billing.rb
#
# frozen_string_literal: true

# Require billing dependencies
# Note: This file loads when billing is enabled, so billing app should be available
require_relative '../../../billing/models/plan'
require_relative '../../../billing/lib/plan_resolver'

module Auth::Config::Hooks
  # Billing - Plan selection carry-through after authentication
  #
  # Captures plan selection from pricing page URLs and provides redirect
  # information in auth responses to continue the checkout flow.
  #
  # ## Flow
  #
  # 1. User visits pricing page: /pricing/identity_plus_v1/monthly
  # 2. User clicks "Get Started" -> redirected to signup with query params
  # 3. Frontend passes `product` and `interval` to signup/login
  # 4. On successful auth, this hook:
  #    a. Validates the plan exists in catalog
  #    b. Stores plan selection in session
  #    c. Adds `billing_redirect` to JSON response
  # 5. Frontend reads redirect and navigates to checkout
  #
  # ## Query Parameters
  #
  # - `product`: Plan identifier (e.g., 'identity_plus_v1')
  # - `interval`: Billing interval ('monthly' or 'yearly')
  #
  # ## JSON Response Enhancement
  #
  # When plan params are present and valid, adds to json_response:
  #
  #   {
  #     "billing_redirect": {
  #       "product": "identity_plus_v1",
  #       "interval": "monthly",
  #       "plan_id": "identity_plus_v1_monthly",
  #       "tier": "identity",
  #       "valid": true
  #     }
  #   }
  #
  # If params are invalid:
  #
  #   {
  #     "billing_redirect": {
  #       "product": "unknown_plan",
  #       "interval": "monthly",
  #       "valid": false,
  #       "error": "Plan not found: unknown_plan_monthly"
  #     }
  #   }
  #
  module Billing
    SESSION_KEY_PRODUCT  = :billing_product
    SESSION_KEY_INTERVAL = :billing_interval

    def self.configure(auth)
      # ========================================================================
      # HOOK: Before Login Attempt - Capture Plan Selection
      # ========================================================================
      #
      # Captures plan selection params early in the auth flow and stores
      # them in the session. This ensures they survive the full auth process
      # including MFA flows.
      #
      auth.before_login_attempt do
        capture_plan_selection
      end

      # ========================================================================
      # HOOK: Before Create Account - Capture Plan Selection
      # ========================================================================
      #
      # Same as before_login_attempt but for signup flow.
      #
      auth.before_create_account do
        capture_plan_selection
      end

      # ========================================================================
      # HOOK: After Login - Add Billing Redirect to Response
      # ========================================================================
      #
      # After successful login (but before MFA if required), include billing
      # redirect info in the JSON response. The frontend uses this to redirect
      # to checkout after completing the full auth flow.
      #
      auth.after_login do
        add_billing_redirect_to_response if json_request?
      end

      # ========================================================================
      # HOOK: After Account Creation - Add Billing Redirect to Response
      # ========================================================================
      #
      # After successful signup, include billing redirect info in the JSON
      # response. For new accounts, the redirect happens after any verification
      # flow is complete.
      #
      auth.after_create_account do
        add_billing_redirect_to_response if json_request?
      end

      # ========================================================================
      # HOOK: After Two-Factor Authentication - Add Billing Redirect
      # ========================================================================
      #
      # After MFA verification completes, check for stored plan selection
      # and add redirect info to the response. This ensures the billing
      # flow continues even after MFA interruption.
      #
      auth.after_two_factor_authentication do
        add_billing_redirect_to_response if json_request?
      end
    end

    # Captures plan selection from request params into session
    #
    # Called by before_login_attempt and before_create_account hooks.
    # Runs in the Rodauth context (self is the Rodauth instance).
    #
    # @return [void]
    def self.define_capture_method(auth)
      auth.define_method(:capture_plan_selection) do
        product  = param_or_nil('product')
        interval = param_or_nil('interval')

        return unless product || interval

        # Store whatever params were provided (validation happens later)
        session[SESSION_KEY_PRODUCT]  = product  if product
        session[SESSION_KEY_INTERVAL] = interval if interval

        Auth::Logging.log_auth_event(
          :billing_plan_captured,
          level: :debug,
          product: product,
          interval: interval,
          correlation_id: session[:auth_correlation_id],
        )
      end
    end

    # Adds billing redirect information to JSON response
    #
    # Called by after_login, after_create_account, and after_two_factor_authentication hooks.
    # Validates the plan and includes redirect info for the frontend.
    #
    # @return [void]
    def self.define_redirect_method(auth)
      auth.define_method(:add_billing_redirect_to_response) do
        product  = session[SESSION_KEY_PRODUCT]
        interval = session[SESSION_KEY_INTERVAL]

        # No plan selection params stored
        return unless product || interval

        # Build redirect info
        redirect_info = build_billing_redirect_info(product, interval)

        # Add to JSON response for frontend
        json_response[:billing_redirect] = redirect_info

        Auth::Logging.log_auth_event(
          :billing_redirect_added,
          level: :info,
          product: product,
          interval: interval,
          valid: redirect_info[:valid],
          error: redirect_info[:error],
          correlation_id: session[:auth_correlation_id],
        )

        # Clear session keys after use (one-time redirect)
        session.delete(SESSION_KEY_PRODUCT)
        session.delete(SESSION_KEY_INTERVAL)
      end
    end

    # Builds billing redirect info hash for JSON response
    #
    # @return [void]
    def self.define_build_method(auth)
      auth.define_method(:build_billing_redirect_info) do |product, interval|
        # Require billing to be enabled
        unless billing_enabled?
          return {
            product: product,
            interval: interval,
            valid: false,
            error: 'Billing not enabled',
          }
        end

        # Validate params are present
        unless product && interval
          return {
            product: product,
            interval: interval,
            valid: false,
            error: 'Missing product or interval',
          }
        end

        # Resolve plan from catalog
        result = ::Billing::PlanResolver.resolve(product: product, interval: interval)

        if result.success?
          {
            product: product,
            interval: interval,
            plan_id: result.plan_id,
            tier: result.tier,
            billing_cycle: result.billing_cycle,
            valid: true,
          }
        else
          {
            product: product,
            interval: interval,
            valid: false,
            error: result.error,
          }
        end
      end
    end

    # Checks if billing is enabled
    #
    # @return [void]
    def self.define_billing_enabled_method(auth)
      auth.define_method(:billing_enabled?) do
        Onetime.conf.dig('billing', 'enabled').to_s == 'true'
      end
    end

    # Call all define methods to register helpers
    def self.configure(auth)
      define_capture_method(auth)
      define_redirect_method(auth)
      define_build_method(auth)
      define_billing_enabled_method(auth)

      # Now configure the hooks that use these methods
      configure_hooks(auth)
    end

    # Configure the actual hooks
    def self.configure_hooks(auth)
      auth.before_login_attempt do
        capture_plan_selection
      end

      auth.before_create_account do
        capture_plan_selection
      end

      auth.after_login do
        add_billing_redirect_to_response if json_request?
      end

      auth.after_create_account do
        add_billing_redirect_to_response if json_request?
      end

      auth.after_two_factor_authentication do
        add_billing_redirect_to_response if json_request?
      end
    end
  end
end
