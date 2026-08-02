# apps/web/auth/config/overrides/account_enumeration.rb
#
# frozen_string_literal: true

require 'argon2'

#
# Account-Enumeration Safety: login, create-account, unlock-account-request
# (security audit 2026-08-02, findings M-1, M-2, L-6)
#
# MECHANISM: a PREPENDED module (RouteScopedGuards) rather than the
# `auth_class_eval` class-level defs used by the sibling override files. The
# reason is composition: config/overrides/reset_password_enumeration.rb already
# defines `account_from_login` at the class level, and a second class-level
# definition would silently clobber it (same last-writer-wins semantics as
# hooks; see config/hooks.rb and #3275). Prepending puts these methods BEFORE
# the class in the ancestry, so `super` falls through to the reset override's
# class-level def and from there to the stock Rodauth feature modules. Every
# override below is scoped by `current_route`, which is nil under
# `internal_request` (the internal dispatch calls `_handle_*` directly and
# never sets @current_route), so internal callers — e.g. the invite flow's
# `Auth::Config.create_account` in apps/api/invite/logic/invites/
# signup_and_accept.rb, which RELIES on duplicate emails raising
# Rodauth::InternalRequestError — keep stock error behavior.
#
# WHAT EACH FINDING NEEDED
# ------------------------
# M-1 (login): stock Rodauth answers an unknown email with
#   ["login", "no matching login"] and a known email + wrong password with
#   ["password", "invalid password"] (both 401). Message AND field name are a
#   single-request account-existence oracle (CWE-204). Fix: one generic
#   message for both branches (GENERIC_LOGIN_MESSAGE, matching the simple-mode
#   AuthenticateSession string) and one field (password_param) via the
#   throw_error_reason override. The generic message is LOGIN-ROUTE-SCOPED:
#   invalid_password_message is shared by the authenticated password-confirm
#   routes (close_account, change_password via invalid_previous_password_
#   message, otp/webauthn setup) whose dialogs have no email field and whose
#   SPA views render the field error verbatim, so those routes keep the stock
#   "invalid password" (see the RouteScopedGuards override). Timing: the wrong-password branch performs an
#   Argon2id verification (~10s of ms at m_cost=16/64MiB); the unknown-email
#   branch performed none, a measurable timing oracle. account_from_login now
#   verifies the submitted password against a PRECOMPUTED dummy hash on the
#   miss path — via the same private password_hash_match? the real branch
#   uses, so the argon2_secret / argon2_old_secret retry behavior is identical.
#   The dummy hash is built ONCE at configure time (per-request
#   Argon2::Password.create would double the cost and invert the skew).
#
# M-2 (create-account): stock Rodauth (a) short-circuits duplicate UNVERIFIED
#   accounts inside verify_account's `new_account` with a 403
#   "awaiting verification" error BEFORE password validation, and (b) surfaces
#   duplicate verified accounts via the before_create_account hook's error
#   throw / save_account's "already an account with this login". Both disclose
#   registration state. Fix: `new_account` below bypasses (a) so every signup
#   follows the same validation path, and the duplicate branches in
#   hooks/account.rb (before_create_account) + the `save_account` race
#   fallback below respond with duplicate_signup_success_response — the exact
#   response a FRESH signup returns (create_account_response), including the
#   billing-redirect JSON parity keys. For unverified duplicates the
#   verification email is re-sent (throttled by Rodauth's
#   verify_account_skip_resend_email_within), so the "email has been sent"
#   success is also true.
#
# L-6 (unlock-account-request): stock Rodauth answers 200 "email sent" for a
#   locked account and 401 "No matching login" for a non-existent OR
#   not-locked account. Fix: all branches (missing account, not locked,
#   recently-sent throttle) respond with unlock_account_request_response — the
#   same generic success the locked-account path returns. The resend throttle
#   is preserved (no email is sent on the throttled/miss/not-locked paths).
#
# HALT CONTRACT
# -------------
# The generic responses are produced by Rodauth's `response` macro methods
# (create_account_response / unlock_account_request_response), which run
# through require_response — Rodauth RAISES if the response does not halt, so
# unlike the reset-password override these paths fail LOUD rather than open if
# a future Rodauth changes halt semantics. Pinned against Rodauth 2.44.0.
#
# RESIDUAL: TIMING SIDE-CHANNELS (accepted, same rationale as
# reset_password_enumeration.rb) — the duplicate-signup and unlock paths halt
# without the DB writes/email dispatch of their genuine counterparts, and the
# login miss path skips the account_password_hashes SELECT (the dummy Argon2
# verification closes the dominant gap). Content equalization is the
# meaningful fix; padding is DoS-amplifying theater. Also accepted: an
# existing account with NO Rodauth hash takes the Redis password-migration
# path (config/overrides/password_migration.rb), whose latency differs — that
# population shrinks to zero as migration completes.
#
# See also: config/overrides/reset_password_enumeration.rb (#3857, the same
# treatment for reset-password-request) and config/rodauth_overrides.rb
# (verify_account error-flash genericization).
#
module Auth::Config::Overrides
  module AccountEnumeration
    # Matches the simple-mode message in
    # apps/web/core/logic/authentication/authenticate_session.rb so both auth
    # modes present the same generic credential error.
    GENERIC_LOGIN_MESSAGE = 'Invalid email or password'

    class << self
      # Frozen, precomputed Argon2id hash used to equalize login timing for
      # non-existent accounts (M-1). Built once at configure time.
      attr_reader :dummy_password_hash
    end

    def self.configure(auth)
      # M-1: generic message for the login route's "no matching login"
      # branch. Set GLOBALLY on purpose — its only reachable consumers among
      # the enabled features are (a) the login route (genericized here), (b)
      # reset-password-request and unlock-account-request, whose miss
      # branches halt with generic successes BEFORE this message is used
      # (reset_password_enumeration.rb / the L-6 overrides below), and (c)
      # webauthn-login's unknown-email branch, where the generic message is
      # equally correct — the stock "no matching login" would be the same
      # existence oracle there.
      #
      # invalid_password_message is deliberately NOT set here: it is shared
      # by authenticated password-confirmation routes (close_account,
      # change_password, otp/webauthn setup) whose dialogs have no email
      # field — CloseAccount.vue renders the field error verbatim — so it is
      # scoped to :login in RouteScopedGuards and keeps the stock
      # "invalid password" everywhere else.
      auth.no_matching_login_message GENERIC_LOGIN_MESSAGE

      @dummy_password_hash ||= build_dummy_password_hash

      auth_class = auth.instance_variable_get(:@auth)
      auth_class.prepend(RouteScopedGuards)
    end

    # Mirrors the cost selection in config/features/argon2.rb (production
    # t_cost=2, m_cost=16 (64 MiB), p_cost=1; reduced in test) and folds in
    # ARGON2_SECRET when configured, so verifying against this hash costs the
    # same as verifying against a real account's hash.
    def self.build_dummy_password_hash
      params = if ENV['RACK_ENV'] == 'test'
                 { t_cost: 1, m_cost: 5, p_cost: 1 }
               else
                 { t_cost: 2, m_cost: 16, p_cost: 1 }
               end

      secret          = Onetime.auth_config.argon2_secret
      params[:secret] = secret if secret

      ::Argon2::Password.new(params).create('rodauth-enumeration-timing-pad').freeze
    end

    # Route-scoped method overrides, prepended onto Auth::Config (see header).
    module RouteScopedGuards
      # M-1 (:login): dummy-verify to equalize timing; the route then emits
      #   the (now generic) no_matching_login error via throw_error_reason.
      # L-6 (:unlock_account_request): non-existent login answers with the
      #   same generic success a locked account gets. HALTS (require_response).
      def account_from_login(login)
        account = super

        if account.nil?
          case current_route
          when :login
            equalize_missing_account_login_timing
          when :unlock_account_request
            Auth::Logging.log_auth_event(
              :unlock_account_request_no_account,
              level: :info,
              email: login, # obscured by log_auth_event
            )
            unlock_account_request_response
          end
        end

        account
      end

      # M-1: generic credential message on the LOGIN ROUTE ONLY. This method
      # is consulted by every password-confirmation flow (close_account,
      # change_password via invalid_previous_password_message, otp/webauthn
      # setup) — authenticated routes with no email field whose SPA views
      # (e.g. CloseAccount.vue) render the field error verbatim, where
      # "Invalid email or password" would be nonsense. `super` preserves the
      # stock (translatable) "invalid password" there. current_route is nil
      # under internal_request, so internal callers also keep stock.
      def invalid_password_message
        current_route == :login ? GENERIC_LOGIN_MESSAGE : super
      end

      # M-1: collapse the no-matching-login field-error onto the SAME field the
      # invalid-password branch uses. With the messages already identical on
      # this route (invalid_password_message above), the ["login", ...] vs
      # ["password", ...] tuple was the remaining single-request
      # distinguisher. Statuses already match (both 401).
      def throw_error_reason(reason, status, field, message)
        if reason == :no_matching_login && current_route == :login
          super(reason, status, password_param, message)
        else
          super
        end
      end

      # L-6: account exists but is NOT locked — stock code falls into the same
      # "No matching login" else-branch as a missing account, which discloses
      # lock state. Respond with the generic success instead. HALTS.
      def get_unlock_account_key
        key = super

        if key.nil? && current_route == :unlock_account_request
          Auth::Logging.log_auth_event(
            :unlock_account_request_not_locked,
            level: :info,
            account_id: account_id,
          )
          unlock_account_request_response
        end

        key
      end

      # L-6: unlock email recently sent — keep the throttle (do NOT resend)
      # but answer with the same generic success, mirroring the
      # reset_password_email_recently_sent? treatment in
      # reset_password_enumeration.rb. HALTS on the throttled path.
      def unlock_account_email_recently_sent?
        return super unless current_route == :unlock_account_request
        return false unless super

        Auth::Logging.log_auth_event(
          :unlock_account_request_recently_sent,
          level: :info,
          account_id: account_id,
        )
        unlock_account_request_response
      end

      # M-2: bypass verify_account's `new_account` override, which answers a
      # duplicate UNVERIFIED account with a 403 "awaiting verification" error
      # BEFORE password validation runs (an existence oracle that also skips
      # the validation steps a fresh signup goes through). _new_account is the
      # stock create_account behavior; the duplicate is then handled
      # post-validation by before_create_account (hooks/account.rb) with a
      # generic success. Internal requests (current_route nil) keep the stock
      # short-circuit.
      def new_account(login)
        if current_route == :create_account
          @account = _new_account(login)
        else
          super
        end
      end

      # M-2 (race window): two concurrent signups for the same email can both
      # pass before_create_account's duplicate check; the loser's INSERT hits
      # the uniqueness constraint and stock Rodauth answers "already an
      # account with this login". Answer with the generic success instead.
      def save_account
        saved = super

        if !saved && current_route == :create_account
          Auth::Logging.log_auth_event(
            :registration_duplicate_insert_race,
            level: :info,
            email: OT::Utils.obscure_email(param(login_param)),
          )
          duplicate_signup_success_response
        end

        saved
      end

      private

      # M-1 timing pad: verify the submitted password against the precomputed
      # dummy hash through the SAME private password_hash_match? the real
      # wrong-password branch uses (identical argon2_secret/argon2_old_secret
      # behavior). Result deliberately discarded; the account remains nil and
      # the route emits the generic error.
      def equalize_missing_account_login_timing
        password_hash_match?(
          AccountEnumeration.dummy_password_hash,
          param_or_nil(password_param).to_s,
        )
        nil
      end

      # M-2: respond to a duplicate-email signup EXACTLY as a fresh signup
      # responds (same notice flash, same 200 success shape, same billing
      # parity keys), so the HTTP response no longer discloses registration
      # state. Called from before_create_account (hooks/account.rb) and the
      # save_account race fallback above. HALTS via create_account_response
      # (require_response enforces the halt).
      #
      # SECURITY: the generic-success treatment applies ONLY to the HTTP
      # create-account route. Under internal_request (current_route is nil —
      # e.g. the invite flow's Auth::Config.create_account), a duplicate MUST
      # still raise: set_error_flash raises InternalRequestError there
      # (internal_request.rb), preserving the pre-M-2 contract. A silent
      # generic success would let the invite flow treat "account already
      # exists" as a fresh signup and establish a session on the EXISTING
      # account without ever verifying its password — an account takeover.
      #
      # @param existing_account [Hash, nil] the existing accounts row, when
      #   the caller has it (enables the unverified-resend courtesy below).
      def duplicate_signup_success_response(existing_account: nil)
        unless current_route == :create_account
          set_error_flash(create_account_error_flash)
          request.env['rodauth.error_flash'] = create_account_error_flash
          throw_rodauth_error
        end

        resend_verification_for_unverified_duplicate(existing_account) if existing_account

        # Billing parity: the fresh-signup path adds billing_redirect JSON keys
        # in after_create_account when plan params were captured. Mirror that
        # here so a probe carrying product/interval params cannot use the key's
        # absence as an oracle. Method exists only when billing is enabled.
        if json_request? && respond_to?(:add_billing_redirect_to_response)
          add_billing_redirect_to_response
        end

        create_account_response
      end

      # M-2 courtesy + honesty: when the duplicate is an UNVERIFIED account,
      # re-send its verification email (best-effort, throttled by Rodauth's
      # verify_account_skip_resend_email_within) so the generic "email has
      # been sent" success is literally true and a legitimate user who lost
      # the first email gets unstuck. Guarded on verify_account being enabled
      # (disabled in test mode). Failure never alters the response —
      # enumeration safety does not depend on the email.
      def resend_verification_for_unverified_duplicate(existing_account)
        return unless respond_to?(:verify_account_email_resend)
        return unless existing_account[account_status_column] == account_unverified_status_value

        Onetime::ErrorHandler.safe_execute(
          'resend_verify_email_duplicate_signup',
          account_id: existing_account[account_id_column],
        ) do
          # Point the Rodauth account context at the EXISTING row (we halt
          # immediately after, so the in-flight new-account hash is dead).
          @account = existing_account

          if allow_resending_verify_account_email? && !verify_account_email_recently_sent?
            verify_account_email_resend

            Auth::Logging.log_auth_event(
              :verify_email_resent_duplicate_signup,
              level: :info,
              account_id: account_id,
              email: OT::Utils.obscure_email(existing_account[login_column]),
            )
          end
        end
      end
    end
  end
end
