# lib/onetime/session/customer_session_evaluator.rb
#
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
        if status == :authenticated && (principal.nil? || customer.nil?)
          raise ArgumentError, 'an authenticated verdict requires a principal and a customer'
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
      return from_memo if @env.is_a?(Hash) && @env.key?(ENV_KEY)

      verdict       = evaluate_uncached
      @env[ENV_KEY] = verdict if @env.is_a?(Hash)
      verdict
    end

    private

    def from_memo
      with_caller_boundary(@env[ENV_KEY])
    end

    # The memo is keyed by request, not by caller. A verdict cached by a caller
    # without +before_active+ (a public route, a view, a compatibility helper)
    # has not been through this caller's boundary, so an authenticated memo is
    # re-judged against it before it is returned. A refusal replaces the memo:
    # the request is refused for every later reader too.
    def with_caller_boundary(cached)
      return cached unless @before_active && cached.authenticated?

      boundary_verdict = @before_active.call(cached.principal)
      return cached unless boundary_verdict

      @env[ENV_KEY] = boundary_verdict
    end

    def evaluate_uncached
      return verdict(:anonymous, :session_missing) unless @session
      return verdict(:mfa_pending, :awaiting_mfa) if @session['awaiting_mfa'] == true
      return verdict(:anonymous, :not_authenticated) unless @session['authenticated'] == true

      external_id = @session['external_id']
      return verdict(:rejected, :identity_missing) if external_id.to_s.empty?
      # No Rack env (a bare helper harness) means no resolved surface to match:
      # refuse, as the compatibility helper did before the evaluator.
      return verdict(:rejected, :surface_mismatch) unless @env.is_a?(Hash)

      case SessionSurface.match_status(@session, @env)
      when :mismatch
        return verdict(:rejected, :surface_mismatch)
      when :unavailable
        # The request's surface could not be read, which says nothing about
        # whether the session belongs here. The customer store is the same
        # datastore, so this is its outage verdict: refuse, keep the session.
        return verdict(:unavailable, :customer_unavailable)
      end

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

    # Session identity is resolved by extid ONLY. Email fallback is deliberately
    # excluded: session +external_id+ is meant to carry an extid (+ur_...+), and
    # if it ever holds an email (data corruption, bug, or a hostile write) an
    # email fallback would resolve whichever account owns that email — a
    # cross-identity resolution the anonymous compatibility path never allowed.
    # Operator-supplied identifiers (e.g. impersonation redemption) use a
    # different, broader loader under a different threat model.
    #
    # The rescue boundary matches the former anonymous compatibility loader's:
    # customer storage failures and the predicates that immediately verify the
    # loaded record return the typed unavailable verdict, so public routes
    # remain reachable while protected routes see the refusal. The surface
    # check reaches the same verdict when it cannot read the request's
    # surface (Onetime::SessionSurface.match_status). Caller-owned,
    # active-session, and impersonation errors remain outside this boundary
    # and retain their existing handling.
    def resolve_customer(external_id)
      Customer.find_by_extid(external_id)
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
