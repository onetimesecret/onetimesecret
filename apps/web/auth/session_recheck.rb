# apps/web/auth/session_recheck.rb
#
# frozen_string_literal: true

require 'onetime/session/customer_session_evaluator'

#
# The /auth router's own surface and active-session check, for the Rack
# sessions the shared evaluator answers before it reaches those two checks.
#
# WHY /auth NEEDS ITS OWN CHECK
#   Onetime::CustomerSessionEvaluator decides in a fixed, normative order:
#   session, MFA, the app-level `authenticated` flag, external identity, tenant
#   surface, customer load, suspension, credential watermark, the caller-owned
#   boundary, the active-session row, impersonation. Everywhere else in the
#   application that order is safe, because every other reader authorizes from
#   the evaluator's verdict: a session that is not `authenticated` gets
#   nothing, so it does not matter that its surface and its active-session row
#   were never looked at.
#
#   The /auth surface is different. Rodauth authorizes from `account_id` alone
#   (`rodauth.logged_in?` is `session['account_id']` being present; the
#   session_key is configured as that string in config/base.rb). Two kinds of
#   Rack session are logged in to Rodauth without carrying the app-level
#   `authenticated` flag, which only Auth::Operations::SyncSession writes
#   (from after_login and after_two_factor_authentication):
#
#     - MFA-pending sessions. after_login ran PrepareMfaSession instead of
#       SyncSession. The evaluator answers :awaiting_mfa before the surface
#       check and before the active-session check, and the router then lets
#       the session reach the second-factor completion routes. Without a
#       check here, a session whose active-session row was revoked during the
#       challenge, or one replayed on another surface, could still complete
#       otp-auth / webauthn-auth / recovery-auth and become fully
#       authenticated.
#     - Autologin sessions. The verify_account autologin (Rodauth default:
#       on) and the invite-signup create_account autologin call
#       `login_session` directly and never fire after_login, so SyncSession
#       never runs. (reset_password_autologin? is off, Rodauth's default; it
#       would take the same path if enabled.) The
#       evaluator answers :not_authenticated, yet Rodauth serves
#       /auth/account, change-password, passkey removal and the rest of its
#       login-required routes to that session.
#
#   Both kinds carry everything the two checks need: every `login_session`
#   passes through `update_session`, where the join key
#   (config/features/active_sessions.rb) and the surface marker
#   (config/overrides/surface_binding.rb) are stamped.
#
# WHAT THIS DOES NOT DO
#   It does not reorder the shared evaluator; MFA still short-circuits first
#   for every other caller. It only adds, on the one surface where
#   `account_id` alone authorizes, the two checks the evaluator had not yet
#   reached when it answered.
#
# WHERE THIS LIVES: a plain module beside the router, with no dependency on
# the Rodauth configuration, so the router and its unit spec
# (spec/unit/router_customer_session_gate_spec.rb) call the same code. The
# spec used to carry a hand-copied fragment of the route block, which could
# drift from it.
#
module Auth
  module SessionRecheck
    extend self

    # Reasons the evaluator returns BEFORE its surface check. A
    # Rodauth-logged-in session with one of these has had neither its surface
    # nor its active-session row examined.
    BEFORE_SURFACE = [:awaiting_mfa, :not_authenticated].freeze

    # Reasons the evaluator returns before its active-session check which are
    # not definitive: the customer store, or the request's surface, could not
    # be read, so only the row is left to examine.
    BEFORE_ACTIVE_SESSION = [:customer_unavailable].freeze

    # The reason the /auth router acts on: the evaluator's own, or the result
    # of the surface / active-session check the evaluator did not reach.
    #
    # Invariant: the definitive rejections (:identity_missing,
    # :customer_not_found, :account_suspended, :stale_credentials,
    # :admin_session_expired) are returned untouched and the gate is never
    # consulted for them. The router destroys those sessions; a fallback
    # :active_session_unavailable would replace that with a refusal that
    # keeps the cookie.
    #
    # The gate call refreshes the row's `last_use` (throttled, see
    # Onetime::ActiveSessionGate). For an MFA-pending session that keeps the
    # row of a live challenge fresh, which is the intended reading of
    # "in use".
    #
    # @param verdict [Onetime::CustomerSessionEvaluator::Verdict]
    # @param session [#[]] the Rack session (string keys)
    # @param env [Hash] the Rack env
    # @return [Symbol] one of Onetime::CustomerSessionEvaluator::REASONS
    def reason_for(verdict, session, env)
      reason = verdict.reason
      return reason if verdict.authenticated?
      return reason unless rodauth_logged_in?(session)

      if BEFORE_SURFACE.include?(reason)
        # The evaluator's own mapping: an unreadable surface is its outage
        # verdict, which keeps the session, never a mismatch, which destroys it.
        case Onetime::SessionSurface.match_status(session, env)
        when :mismatch then return :surface_mismatch
        when :unavailable then reason = :customer_unavailable
        end
      elsif !BEFORE_ACTIVE_SESSION.include?(reason)
        return reason
      end

      case Onetime::ActiveSessionGate.verdict(session, env: env)
      when :revoked
        :active_session_revoked
      when :unavailable
        :active_session_unavailable
      else
        reason
      end
    end

    # Rodauth's notion of logged in, read the way Rodauth and
    # Onetime::ActiveSessionGate read it: the configured session_key
    # ('account_id', a string key) holding a value. A genuinely anonymous
    # Rack session has none, and neither check applies to it.
    def rodauth_logged_in?(session)
      session.respond_to?(:[]) && !session['account_id'].to_s.empty?
    end
  end
end
