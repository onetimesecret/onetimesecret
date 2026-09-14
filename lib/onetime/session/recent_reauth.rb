# lib/onetime/session/recent_reauth.rb
#
# frozen_string_literal: true

require_relative 'surface'

module Onetime
  # Recent full re-authentication proof (#4410, epic #4408).
  #
  # An authenticated session, on its own, does not prove that the account
  # recently completed a full local authentication ceremony. Identity
  # attachment (platform Connect, tenant Connect) needs a stronger, time-
  # bounded proof: primary local credential plus every MFA factor required by
  # account policy, completed on THIS session, on THIS surface, against THIS
  # account, within an explicit window.
  #
  # This module is that proof, and the single gate that reads it. The gate
  # is reused by both platform Connect (#4411) and tenant Connect (#3849).
  #
  # ## The four bindings
  #
  # A proof carries four values:
  #
  #     { 'account_id' => ..., 'at' => ..., 'surface' => ..., 'methods' => ... }
  #
  # - `account_id` — the numeric account id whose credentials were verified.
  #   The gate refuses a proof intended for a different account.
  # - `at` — the Unix time (integer UTC seconds) at which the ceremony
  #   completed. The gate refuses a proof older than the caller-supplied
  #   `max_age:`.
  # - `surface` — the {Onetime::SessionSurface} descriptor of the surface on
  #   which the ceremony completed. The gate refuses a proof for a
  #   different surface, and refuses when the current request's surface is
  #   unresolved. This is a strict equality check, independent of and
  #   composed with the session's own surface binding.
  # - `methods` — an ordered list of the factors that were completed
  #   ('password', 'webauthn', 'totp', 'recovery_code'). The gate requires
  #   the first entry to be an explicitly allowed local primary, and the list
  #   also lets support distinguish password + MFA from WebAuthn primary.
  #
  # A session's proof lives in the Rack session under {KEY}. It is bound to
  # the session by construction: it is stored inside the session blob, and
  # a different Rack session (different sid, different cookie) has its own.
  #
  # ## What counts as a full ceremony
  #
  # Recording is done from the login-completion hooks in
  # apps/web/auth/config/hooks/. Two call sites:
  #
  # - `after_login`, when the account requires no MFA (or the primary
  #   credential is a passkey that Rodauth has accepted as covering the MFA
  #   requirement — {WebAuthn as primary} in the epic's language).
  # - `after_two_factor_authentication`, on every successful second factor
  #   (OTP, recovery code, WebAuthn-as-2FA).
  #
  # Four cases MUST NOT record proof:
  #
  # - **Platform mailbox proof** (email_auth / magic link). Possession of an
  #   inbox is not a local credential; it is a recovery-class ceremony. If
  #   a magic link's after_login runs alone (no MFA required), no proof.
  # - **Existing authenticated session**. Merely being signed in is not
  #   proof — this module has no "extend on request" path. A proof ages
  #   out; the session's own lifetime is independent.
  # - **SSO callback** (omniauth). Federated proof is not local proof.
  #   Neither the after_login of an omniauth login, nor the second factor
  #   completion of an SSO account, records here.
  # - **Password-only step that bypasses required MFA**. If the account has
  #   MFA required and the login stopped at the password prompt, no proof
  #   — the after_login branch skips recording precisely because the login
  #   is incomplete; only after_two_factor_authentication may record.
  #
  # ## The gate is one function
  #
  # `Onetime::RecentReauth.satisfied?(session, env, account_id:, max_age:)`
  # returns true iff every binding matches. Every caller in the auth,
  # billing, and Connect stacks funnels through here; no bespoke checks.
  #
  # ## Fail-closed
  #
  # A missing marker, a nil surface (session or request), an account_id
  # mismatch, or a stale `at` all return false. There is no soft outcome —
  # the gate is called before minting a Connect intent or binding an
  # identity, and both must refuse rather than proceed on an unanswered
  # question.
  module RecentReauth
    KEY = 'recent_reauth'

    # A proof is valid only when its first completed method is an explicitly
    # reviewed local primary. Positive matching keeps unknown, remembered,
    # mailbox, and federated methods fail-closed.
    LOCAL_PRIMARIES = %w[password webauthn].freeze

    class << self
      # Record a proof onto the session. Returns the stored payload, or
      # nil when the request has no authoritative surface (in which case
      # nothing is recorded).
      #
      # @param session [Hash] Rack session; persisted keys and values are strings
      # @param env [Hash] Rack env, for {Onetime::SessionSurface.for_env}
      # @param account_id [Integer] the account whose credentials were verified
      # @param methods [Array<String>] the ordered list of completed factors
      #   as observed by the caller (e.g. Rodauth's `authenticated_by`)
      # @param now [Time] override for the recorded timestamp (test seam)
      # @return [Hash, nil] the frozen payload actually stored, or nil
      def record(session, env, account_id:, methods:, now: Time.now)
        surface           = SessionSurface.for_env(env)
        completed_methods = Array(methods).map(&:to_s).freeze
        return nil if surface.nil?
        return nil if account_id.nil?
        return nil unless LOCAL_PRIMARIES.include?(completed_methods.first)

        payload      = {
          'account_id' => Integer(account_id),
          'at' => now.utc.to_i,
          'surface' => surface,
          'methods' => completed_methods,
        }.freeze
        session[KEY] = payload
      end

      # The gate. True iff a proof is present, is for this account, was
      # produced on this request's surface, and is not older than
      # `max_age` seconds.
      #
      # @param session [Hash, nil] Rack session
      # @param env [Hash, nil] Rack env
      # @param account_id [Integer] the account the caller is about to
      #   bind an identity for
      # @param max_age [Integer] the maximum age of the proof in seconds
      # @param now [Time] clock override (test seam)
      # @return [Boolean]
      def satisfied?(session, env, account_id:, max_age:, now: Time.now)
        return false if session.nil? || env.nil?
        return false if account_id.nil?

        stored = session[KEY]
        return false unless stored.is_a?(Hash)

        stored_account = stored['account_id']
        return false unless stored_account == Integer(account_id)

        current_surface = SessionSurface.for_env(env)
        return false if current_surface.nil?
        return false unless stored['surface'] == current_surface

        methods = stored['methods']
        return false unless methods.is_a?(Array)
        return false unless LOCAL_PRIMARIES.include?(methods.first)

        at = stored['at']
        return false unless at.is_a?(Integer)
        return false if now.utc.to_i - at > Integer(max_age)
        return false if at > now.utc.to_i # future-dated proof is bogus

        true
      end

      # Read the stored payload without comparison. Callers that need to
      # log the proof or expose it in diagnostics use this; enforcement
      # uses {satisfied?}.
      def recorded(session)
        session[KEY]
      end

      # Clear the marker. Called from logout and any code path that
      # invalidates the proof (e.g. successful identity binding when the
      # proof is single-use).
      def clear(session)
        session.delete(KEY)
      end
    end
  end
end
