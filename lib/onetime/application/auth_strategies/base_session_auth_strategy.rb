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

require_relative '../../session/impersonation'
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
          return failure('[SESSION_MISSING] No session available') unless session

          # Defense-in-depth (M-11): a session mid-MFA must never authenticate a
          # request, even if some future code path sets authenticated=true without
          # clearing this flag. PrepareMfaSession writes the STRING key
          # 'awaiting_mfa'; SyncSession deletes it when MFA completes. Read the
          # string key deliberately — a symbol :awaiting_mfa would silently never
          # match. Guard is nil/false-safe: only == true blocks.
          return failure('[SESSION_AWAITING_MFA] MFA not completed') if session['awaiting_mfa'] == true

          # Check if session is authenticated
          unless session['authenticated'] == true
            return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated')
          end

          external_id = session['external_id']
          if external_id.to_s.empty?
            return failure('[IDENTITY_MISSING] No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.load_by_extid_or_email(external_id)
          return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

          # Suspended accounts are rejected on EVERY request, so a suspension
          # takes effect immediately even for sessions the suspend-time sweep
          # could not see (encrypted payloads). Reversible trust & safety
          # state — see Auth::Operations::Customers::SetSuspension.
          return failure('[ACCOUNT_SUSPENDED] Account suspended') if cust.suspended?

          # Credential watermark (#3810): reject any session authenticated before
          # the customer's last password change/reset. This per-request check —
          # not the enumerative blob deletion in the password hooks, which is
          # hygiene — is the authoritative revocation boundary, so even a blob
          # the hooks never found dies here. See Helpers for the fail-secure /
          # never-mass-logout semantics.
          if session_predates_credential_change?(session, cust)
            return failure('[SESSION_STALE_CREDENTIALS] Session predates last credential change')
          end

          # Admin-surface session bounds (#4331). Runs here because this is the
          # one per-request chokepoint that already has the loaded customer
          # (hence cust.role) and the raw session. Deliberately AFTER the
          # watermark and BEFORE additional_checks.
          #
          # The session is NOT mutated: an auth strategy runs on read paths and
          # must stay side-effect-free, and clearing `authenticated` here would
          # risk a write on a request that should not commit one. Failing is
          # sufficient — the SPA sees the 401 and routes to sign-in, which
          # replaces the session. The env flag is not a session write; it tells
          # TrackMetadata that a REFUSED request is not activity, so the request
          # we are rejecting cannot slide the idle window forward on its way out.
          if (reason = admin_session_expiry_reason(session, cust, env))
            env[AdminSessionLifetime::EXPIRED_ENV_KEY] = reason.to_s
            return failure(
              "[ADMIN_SESSION_EXPIRED] Admin session #{reason} timeout exceeded; sign in again",
            )
          end

          # Colonel impersonation overlay. THE authoritative resolution: this
          # strategy_result.user is what Onetime::Logic::Base#cust returns and
          # what additional_metadata builds user_roles from, so from here down
          # the request IS the target customer — including the role checks
          # that make /api/colonel 403 while impersonating.
          #
          # Deliberately AFTER the suspension and credential-watermark checks
          # above: those judge the PRINCIPAL (the operator), and a suspended or
          # credential-revoked colonel must lose the whole session, not just
          # the overlay.
          cust, = Onetime::SessionImpersonation.resolve(session, cust, env: env)

          # Perform additional checks (role, permissions, etc.)
          check_result = additional_checks(cust, env)
          return check_result if check_result.is_a?(Otto::Security::Authentication::AuthFailure)

          log_success(cust)

          # Load organization and team context
          org_context = load_organization_context(cust, session, env)

          # Build complete metadata hash, then splat it into success()
          metadata_hash = build_metadata(env, additional_metadata(cust)).merge(
            organization_context: org_context,
          )

          success(
            session: session,
            user: cust,
            auth_method: self.class.auth_method_name,
            **metadata_hash,
          )
        end

        protected

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
