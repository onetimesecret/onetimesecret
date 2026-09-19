# lib/onetime/application/auth_strategies/base_session_auth_strategy.rb
#
# frozen_string_literal: true

#
# Base strategy for authenticated routes.
#
# Provides common authentication logic for session-based auth.
# Subclasses can override `additional_checks` for role/permission validation.
#
# @see Onetime::Application::AuthStrategies

require_relative '../../session/customer_session_evaluator'
require_relative '../../session/failure_code'
require_relative 'helpers'
require_relative 'admin_session_lifetime'

module Onetime
  module Application
    module AuthStrategies
      class BaseSessionAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        include AdminSessionLifetime
        include Onetime::Application::OrganizationLoader

        @auth_method_name = nil

        class << self
          attr_reader :auth_method_name
        end

        def authenticate(env, _requirement)
          session = env['rack.session']
          verdict = Onetime::CustomerSessionEvaluator.evaluate(
            session,
            env: env,
            before_active: ->(principal) do
              admin_expiry_verdict(session, principal, env)
            end,
          )
          return failure_for(verdict, env) unless verdict.authenticated?

          cust = verdict.customer

          # Route-specific role and permission checks deliberately remain outside
          # the common customer-session identity verdict.
          check_result = additional_checks(cust, env)
          return check_result if check_result.is_a?(Otto::Security::Authentication::AuthFailure)

          log_success(cust)

          # Load organization and team context
          org_context = load_organization_context(cust, session, env)

          # Build complete metadata hash, then splat it into success()
          metadata_hash = build_metadata(env, additional_metadata(cust)).merge(
            organization_context: org_context,
            customer_session_verdict: verdict,
          )

          success(
            session: session,
            user: cust,
            auth_method: self.class.auth_method_name,
            **metadata_hash,
          )
        end

        protected

        FAILURE_REASONS = {
          session_missing: '[SESSION_MISSING] No session available',
          awaiting_mfa: '[SESSION_AWAITING_MFA] MFA not completed',
          not_authenticated: '[SESSION_NOT_AUTHENTICATED] Not authenticated',
          identity_missing: '[IDENTITY_MISSING] No identity in session',
          surface_mismatch: '[SESSION_SURFACE_MISMATCH] Session surface does not match request; sign in again',
          customer_not_found: '[CUSTOMER_NOT_FOUND] Customer not found',
          account_suspended: '[ACCOUNT_SUSPENDED] Account suspended',
          stale_credentials: '[SESSION_STALE_CREDENTIALS] Session predates last credential change',
          active_session_revoked: '[SESSION_REVOKED] Active-session row revoked; sign in again',
          active_session_unavailable: '[SESSION_UNVERIFIED] Active-session row could not be checked; try again',
          customer_unavailable: '[SESSION_UNVERIFIED] Customer session could not be checked; try again',
        }.freeze

        def admin_expiry_verdict(session, principal, env)
          reason = admin_session_expiry_reason(session, principal, env)
          return nil unless reason

          env[AdminSessionLifetime::EXPIRED_ENV_KEY] = reason.to_s
          Onetime::CustomerSessionEvaluator::Verdict.new(
            status: :rejected,
            reason: :admin_session_expired,
            detail: reason,
          )
        end

        # The typed reason is handed to Onetime::Middleware::SessionFailureCode
        # through the env: Otto renders the 401 body itself from the failure
        # string alone, so the reason would otherwise be collapsed into a
        # bracket marker inside `message` (#4462).
        def failure_for(verdict, env)
          env[Onetime::SessionFailureCode::ENV_KEY] = verdict.reason if env.is_a?(Hash)

          if verdict.reason == :admin_session_expired
            return failure(
              "[ADMIN_SESSION_EXPIRED] Admin session #{verdict.detail} timeout exceeded; sign in again",
            )
          end

          failure(FAILURE_REASONS.fetch(verdict.reason))
        end

        # Override in subclasses to add role/permission checks
        #
        # @param cust [Onetime::Customer] Authenticated customer
        # @param env [Hash] Rack environment
        # @return [Otto::Security::Authentication::AuthFailure, nil] Failure if check fails, nil if passes
        def additional_checks(_cust, _env)
          nil
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
    end
  end
end
