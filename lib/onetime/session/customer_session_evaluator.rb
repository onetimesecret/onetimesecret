# frozen_string_literal: true

require_relative 'active_session_gate'
require_relative 'impersonation'
require_relative 'surface'

module Onetime
  # Resolves the customer-session identity shared by protected routes, public
  # routes, compatibility helpers, and bootstrap serialization.
  #
  # The order is policy and must remain stable:
  # session, MFA, authenticated flag, external identity, tenant surface,
  # customer load, suspension, credential watermark, the caller-owned admin
  # boundary, active-session evaluation, then impersonation.
  #
  # Admin expiry is deliberately not a customer-identity predicate. Protected
  # strategies may supply +before_active+ to enforce it at its existing boundary.
  # Route authorization and organization context run after this evaluator.
  #
  # Full-mode Rack sessions without +active_session_id_hmac+ retain the existing
  # legacy exemption in ActiveSessionGate: the gate returns :skipped. That means
  # only that membership could not be joined and checked; it does not prove an
  # active-session row exists. The exemption is neither widened nor converted
  # into verified membership here.
  class CustomerSessionEvaluator
    ENV_KEY = 'onetime.customer_session_verdict'

    STATUSES = [:authenticated, :anonymous, :mfa_pending, :rejected, :unavailable].freeze

    REASONS = [
      :authenticated,
      :session_missing,
      :awaiting_mfa,
      :not_authenticated,
      :identity_missing,
      :surface_mismatch,
      :customer_not_found,
      :account_suspended,
      :stale_credentials,
      :admin_session_expired,
      :active_session_revoked,
      :active_session_unavailable,
      :customer_unavailable,
    ].freeze

    class Verdict
      attr_reader :status, :reason, :principal, :customer, :impersonation, :detail

      def initialize(status:, reason:, principal: nil, customer: nil, impersonation: nil, detail: nil)
        raise ArgumentError, "unknown customer-session status: #{status}" unless STATUSES.include?(status)
        raise ArgumentError, "unknown customer-session reason: #{reason}" unless REASONS.include?(reason)
        if status != :authenticated && (principal || customer || impersonation)
          raise ArgumentError, 'identity is available only for an authenticated verdict'
        end

        @status        = status
        @reason        = reason
        @principal     = principal
        @customer      = customer
        @impersonation = impersonation
        @detail        = detail
        freeze
      end

      def authenticated?
        status == :authenticated
      end

      def anonymous?
        status == :anonymous
      end

      def mfa_pending?
        status == :mfa_pending
      end

      def rejected?
        status == :rejected
      end

      def unavailable?
        status == :unavailable
      end
    end

    class << self
      def evaluate(session, env:, before_active: nil)
        new(session, env: env, before_active: before_active).evaluate
      end

      def forget(env)
        env.delete(ENV_KEY) if env.is_a?(Hash)
      end
    end

    def initialize(session, env:, before_active: nil)
      @session       = session
      @env           = env
      @before_active = before_active
    end

    def evaluate
      return @env[ENV_KEY] if @env.is_a?(Hash) && @env.key?(ENV_KEY)

      verdict       = evaluate_uncached
      @env[ENV_KEY] = verdict if @env.is_a?(Hash)
      verdict
    end

    private

    def evaluate_uncached
      return verdict(:anonymous, :session_missing) unless @session
      return verdict(:mfa_pending, :awaiting_mfa) if @session['awaiting_mfa'] == true
      return verdict(:anonymous, :not_authenticated) unless @session['authenticated'] == true

      external_id = @session['external_id']
      return verdict(:rejected, :identity_missing) if external_id.to_s.empty?
      return verdict(:rejected, :surface_mismatch) unless SessionSurface.matches_request?(@session, @env)

      principal = resolve_customer(external_id)
      return principal if principal.is_a?(Verdict)
      return verdict(:rejected, :customer_not_found) unless principal

      unavailable = verify_customer(principal)
      return unavailable if unavailable.is_a?(Verdict)
      return verdict(:rejected, :account_suspended) if unavailable == :suspended
      return verdict(:rejected, :stale_credentials) if unavailable == :stale_credentials

      boundary_verdict = @before_active&.call(principal)
      return boundary_verdict if boundary_verdict

      case ActiveSessionGate.verdict(@session, env: @env)
      when :revoked
        return verdict(:rejected, :active_session_revoked)
      when :unavailable
        return verdict(:unavailable, :active_session_unavailable)
      end

      customer, marker = SessionImpersonation.resolve(@session, principal, env: @env)
      verdict(
        :authenticated,
        :authenticated,
        principal: principal,
        customer: customer,
        impersonation: marker,
      )
    end

    # Keep the former anonymous compatibility loader's rescue boundary around
    # customer storage and the predicates that immediately verify the loaded
    # record. Public routes must remain reachable during a customer-store
    # failure, while protected routes receive the typed unavailable verdict.
    # Surface, caller-owned, active-session, and impersonation errors remain
    # outside this boundary and retain their existing handling.
    def resolve_customer(external_id)
      Customer.load_by_extid_or_email(external_id)
    rescue StandardError => ex
      customer_unavailable(ex)
    end

    def verify_customer(principal)
      return :suspended if principal.suspended?
      return :stale_credentials if predates_credential_change?(principal)

      nil
    rescue StandardError => ex
      customer_unavailable(ex)
    end

    def customer_unavailable(ex)
      OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
      OT.ld ex.backtrace.first(3).join("\n")
      verdict(:unavailable, :customer_unavailable)
    end

    def predates_credential_change?(principal)
      watermark = principal.last_password_update.to_i
      return false unless watermark.positive?

      @session['authenticated_at'].to_i <= watermark
    end

    def verdict(status, reason, **)
      Verdict.new(status: status, reason: reason, **)
    end
  end
end
