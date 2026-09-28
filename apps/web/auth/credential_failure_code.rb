# apps/web/auth/credential_failure_code.rb
#
# frozen_string_literal: true

#
# The one seam between Rodauth's error reasons and the stable failure codes
# (#4469; vocabulary in Onetime::SessionFailureCode).
#
# Rodauth renders its own JSON error body and offers no hook into it, but it
# names every error it throws: `set_error_reason(reason)` runs first in
# `throw_error_reason` and `set_response_error_reason_status`, immediately
# before the response is finalized, on every route it serves. The override in
# config/overrides/failure_code.rb calls .record from that method, and the
# Rack middleware (Onetime::Middleware::SessionFailureCode) renders whatever
# reason is left in the env onto the 401. One seam, no per-route edits, and a
# new Rodauth feature's rejections are covered the day it is enabled.
#
# WHERE THIS LIVES. Like restrict_to.rb: a plain module with no boot chain,
# so its unit spec (apps/web/auth/spec/unit/credential_failure_code_spec.rb)
# and the route coverage spec can read the table without configuring Rodauth.
# config/overrides/failure_code.rb is the thin wiring.
#
# THREE OUTCOMES for a Rodauth reason:
#
#   credential   The reason names a credential the request presented and
#                Rodauth rejected. Stashed, replacing the router's anonymous
#                stash (a failed login is answered as a credential refusal,
#                not as "no session"). The code is deliberately coarser than
#                Rodauth's field error: `no matching login` and `invalid
#                password` are one `invalid_credentials`, so the code adds no
#                enumeration surface the message did not already have.
#   session      `login_required` is Rodauth refusing a login-required route
#                to a request it does not consider logged in. The router
#                already stashed why (session_missing / not_authenticated)
#                before r.rodauth, so the stash stands.
#                `two_factor_need_authentication` is Rodauth refusing a route
#                to a session that has presented only its first factor: the
#                evaluator's `awaiting_mfa`, stashed here.
#   none         Every other reason: a key that did not resolve, a malformed
#                parameter, a duplicate, a policy refusal. Whatever the
#                router stashed is withdrawn so the response, if it is a
#                401, stays uncoded: it is not about the session and not
#                about a credential.
#
# Rodauth answers a locked-out account (`account_locked_out`) and an
# unverified one (`unverified_account`) with 403 (`lockout_error_status`,
# `unopen_account_error_status`), and the middleware annotates 401s only, so
# neither carries a code. Both are listed so the choice is visible.
#

require 'onetime/session/failure_code'

module Auth
  module CredentialFailureCode
    # Rodauth reasons that are a rejected credential, and the code each one
    # is answered with.
    CREDENTIAL_REASONS = {
      # POST /auth/login, and every other route that takes the login field
      # (email-auth request, unlock request, verification resend): the login
      # matched no open account.
      no_matching_login: :invalid_credentials,
      # The password: on login, on unlock, and on every password confirmation
      # an account route asks for (change password, change login, close
      # account, OTP setup and disable, passkey setup and removal).
      invalid_password: :invalid_credentials,
      # Second factors during a login or a step-up.
      invalid_otp_auth_code: :invalid_credentials,
      invalid_recovery_code: :invalid_credentials,
      # A passkey assertion that failed verification (401). Rodauth reuses
      # the reason for a malformed assertion too, but answers that with
      # `invalid_field_error_status` (422), which the middleware leaves alone.
      invalid_webauthn_auth_param: :invalid_credentials,
    }.freeze

    # Rodauth reasons that are a refusal of the SESSION, and the evaluator
    # reason each one corresponds to. nil keeps what the router stashed.
    SESSION_REASONS = {
      login_required: nil,
      two_factor_need_authentication: :awaiting_mfa,
    }.freeze

    # Rodauth reasons that are a refusal of a credential but are answered
    # with a status other than 401, so they carry no code. Documented, not
    # acted on: the middleware's 401-only rule is what leaves them uncoded.
    UNCODED_403_REASONS = [
      :account_locked_out,
      :unverified_account,
    ].freeze

    class << self
      # Stash, keep, or withdraw the failure code for a Rodauth error reason.
      #
      # @param env [Hash] the Rack env
      # @param reason [Symbol, nil] the reason Rodauth passed to
      #   set_error_reason
      # @return [Symbol, nil] the reason now stashed
      def record(env, reason)
        key = reason&.to_sym

        if CREDENTIAL_REASONS.key?(key)
          Onetime::SessionFailureCode.stash(env, CREDENTIAL_REASONS.fetch(key))
        elsif SESSION_REASONS.key?(key)
          mapped = SESSION_REASONS.fetch(key)
          Onetime::SessionFailureCode.stash(env, mapped) if mapped
        else
          Onetime::SessionFailureCode.forget(env)
        end

        env.is_a?(Hash) ? env[Onetime::SessionFailureCode::ENV_KEY] : nil
      end
    end
  end
end
