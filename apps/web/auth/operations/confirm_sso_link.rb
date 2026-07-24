# apps/web/auth/operations/confirm_sso_link.rb
#
# frozen_string_literal: true

require 'auth/lib/logging'
require 'auth/operations/bind_sso_identity'
require 'auth/operations/mfa_state_checker'
require 'auth/operations/detect_mfa_requirement'

#
# Consume a mailbox-proof SsoLinkVerification token and bind the SSO identity
# (#3840 Phase 4). This is the orchestration step for the passwordless linking
# flow: load -> atomic single-use consume -> re-verify ownership + credential
# watermark -> (MFA gate) -> bind via the shared primitive -> audit.
#
# It does NOT decide whether mailbox proof was valid — the fact that the token was
# delivered ONLY to the on-file inbox (never in the callback redirect) IS the
# proof, and holding the token is holding that proof. This op re-checks that the
# snapshot still holds (account unchanged, email unchanged, no credential change)
# and performs the bind through Auth::Operations::BindSsoIdentity.
#
# rodauth-INDEPENDENT by construction: it takes `db` explicitly and re-locates the
# account by its snapshotted primary key in `db[:accounts]`. Session establishment
# (login) is NOT its job — that requires a live Rodauth request and is done by the
# calling route (Auth::Routes::SsoLinkConfirm) after this op returns :ok. The op is
# handed `current_sid` (for the soft cross-device check) and `mfa_feature_loaded`
# (whether the OTP feature is present) so it stays free of Rodauth internals.
#
# SECURITY MODEL (mirrors SsoLinkChallenge/LinkSso, mailbox proof replacing the
# password proof):
#   - SINGLE-USE: #delete! is the atomic consume gate. Exactly one of two
#     concurrent consumers gets the delete count 1; the loser gets 0 -> :link_expired.
#     Consumed up front, before the bind, so the token is worth one attempt.
#   - OWNERSHIP RE-CHECK: the account is re-located by the snapshotted account_id and
#     its email must STILL normalize to the token's email. A drift (account re-emailed,
#     or the row gone) fails closed (:link_conflict / :link_expired) rather than
#     binding onto an account the mailbox proof no longer matches.
#   - CREDENTIAL-CHANGE INVALIDATION (criterion 3): the token snapshots
#     Customer#last_password_update at issuance; if it advanced (any password
#     set/reset/change stamps it via UpdatePasswordMetadata) the token is rejected
#     (:link_invalidated). A watermark comparison, not a token-enumeration sweep.
#     An UNREADABLE watermark (probe raises, or the Customer does not resolve) is
#     rejected just as hard — the guard fails secure, never open — but under its
#     OWN status (:link_error), because an outage on our side is not a credential
#     change the user made and must not be reported to them as one.
#   - MFA-SAFE BIND: SSO logins are MFA-exempt, so binding an SSO path before a
#     pending second factor is satisfied would attach an MFA-bypassing login to the
#     account. When the account has a pending second factor the bind is DEFERRED
#     (bound: false); the route still logs the user in, which routes them to the OTP
#     step. Moot for default installs (MFA off) but load-bearing for AUTH_MFA_ENABLED.
#
# Returns a Result (see below). The route maps status -> HTTP:
#   :ok             -> establish session (or MFA hand-off); 200
#   :link_expired   -> 401 (token missing / consumed / expired, or account vanished)
#   :link_conflict  -> 409 (account/email drift, or the identity is owned elsewhere)
#   :link_invalidated -> 409 (a credential change advanced the watermark since issuance)
#   :link_error     -> 409 (the watermark could not be READ — our outage, not their
#                      credential change; terminal all the same, the token is spent)
#
module Auth
  module Operations
    class ConfirmSsoLink
      # @!attribute status [Symbol] :ok | :link_expired | :link_conflict |
      #   :link_invalidated | :link_error
      # @!attribute account_id [String, nil] the bound/target account id (for the route's login)
      # @!attribute email [String, nil] the normalized login the route logs in as
      # @!attribute provider [String, nil] provider name (logging + response context)
      # @!attribute bound [Boolean] whether the identity row was actually bound this call
      # @!attribute second_factor_pending [Boolean] whether the bind was deferred for MFA
      Result = Struct.new(
        :status,
        :account_id,
        :email,
        :provider,
        :bound,
        :second_factor_pending,
        keyword_init: true,
      ) do
        def ok?
          status == :ok
        end
      end

      # @param db [Sequel::Database] the auth database (explicit — NOT rodauth.db, so
      #   the op is usable outside a Rodauth request context)
      # @param token [String] the raw single-use verification token from the email link
      # @param current_sid [String, nil] the current request's session id (soft-bound)
      # @param mfa_feature_loaded [Boolean] whether the OTP feature is enabled for this deploy
      # @return [Result]
      def self.call(db:, token:, current_sid: nil, mfa_feature_loaded: false)
        new(
          db: db, token: token, current_sid: current_sid, mfa_feature_loaded: mfa_feature_loaded,
        ).call
      end

      def initialize(db:, token:, current_sid: nil, mfa_feature_loaded: false)
        @db                 = db
        @token              = token.to_s
        @current_sid        = current_sid.to_s
        @mfa_feature_loaded = mfa_feature_loaded
      end

      # @return [Result]
      def call
        verification = Onetime::SsoLinkVerification.load(@token)
        return expired unless verification

        # SINGLE-USE (atomic): consume NOW, before any bind. #delete! returns the
        # Redis DEL count; exactly one of two racing consumers gets 1.
        return expired unless verification.delete! == 1

        warn_on_cross_device(verification)

        account = @db[:accounts].where(id: verification.account_id.to_i).first
        return expired unless account

        # OWNERSHIP RE-CHECK: the account's email must still normalize to the token's
        # email. A drift means the account was re-emailed since issuance and the
        # mailbox proof no longer matches — never bind.
        if OT::Utils.normalize_email(account[:email]) != verification.email.to_s
          return conflict(verification)
        end

        # CREDENTIAL-CHANGE INVALIDATION (criterion 3). Tri-state on purpose: an
        # unreadable watermark rejects like an advance but carries its own status.
        case watermark_state(account, verification)
        when :advanced   then return invalidated(verification)
        when :unreadable then return probe_failed(verification)
        end

        account_id = verification.account_id

        if second_factor_pending?(account_id)
          Auth::Logging.log_auth_event(
            :sso_link_verification_deferred_mfa,
            level: :warn,
            email: OT::Utils.obscure_email(verification.email),
            provider: verification.provider,
            account_id: account_id,
          )
          return Result.new(
            status: :ok,
            account_id: account_id,
            email: verification.email,
            provider: verification.provider,
            bound: false,
            second_factor_pending: true,
          )
        end

        bind_result = Auth::Operations::BindSsoIdentity.call(
          db: @db,
          account_id: account_id,
          provider: verification.provider,
          issuer: verification.issuer,
          uid: verification.uid,
        )
        return conflict(verification) if bind_result == :conflict

        Auth::Logging.log_auth_event(
          :sso_link_verification_confirmed,
          level: :warn,
          email: OT::Utils.obscure_email(verification.email),
          provider: verification.provider,
          issuer: verification.issuer,
          account_id: account_id,
        )

        Result.new(
          status: :ok,
          account_id: account_id,
          email: verification.email,
          provider: verification.provider,
          bound: true,
          second_factor_pending: false,
        )
      end

      private

      # SOFT session binding: the initiating sid is recorded for observability, but
      # mailbox proof is inherently cross-device (the user may click on their phone),
      # so a mismatch is logged and TOLERATED — never rejected.
      def warn_on_cross_device(verification)
        token_sid = verification.sid.to_s
        return if token_sid.empty? || @current_sid.empty? || token_sid == @current_sid

        Auth::Logging.log_auth_event(
          :sso_link_verification_cross_device,
          level: :info,
          provider: verification.provider,
          account_id: verification.account_id,
        )
      end

      # Has a credential change advanced the account's watermark since issuance?
      # Tri-state: :unchanged (bind may proceed) | :advanced (a real credential
      # change) | :unreadable (the watermark could not be read at all).
      #
      # Resolves the Customer the same way the password hooks do (external_id first,
      # email fallback). An UNRESOLVABLE Customer fails SECURE: :unreadable rejects
      # the token rather than binding without certainty the credential is unchanged.
      #
      # :unreadable is kept DISTINCT from :advanced even though both reject, because
      # they mean opposite things to the person holding the link: :advanced is a
      # credential change THEY made, :unreadable is a datastore outage on OUR side.
      # Collapsing them tells an outage victim their credentials changed and sends
      # them hunting for a change that never happened. Both are equally terminal —
      # the token was consumed above — so the distinction is in the copy, not in
      # whether a retry is offered.
      #
      # BOTH unresolvable shapes count — a raise AND a nil return. The nil is the
      # subtle one: `load_by_extid_or_email` returns nil (it does not raise) for an
      # absent record or an index miss, so a `&.last_password_update.to_i` would
      # yield 0, compare as "not advanced", and let the bind PROCEED — fail-OPEN in
      # exactly the case where the credential state cannot be read. A nil is not a
      # legitimate state here: the account row was already located above, and the
      # issuance side resolved the SAME Customer by the SAME identifier to snapshot
      # the watermark. An account whose Customer cannot be resolved cannot
      # authenticate app-side either (BaseSessionAuthStrategy fails CUSTOMER_NOT_FOUND),
      # so rejecting costs nothing legitimate. Logged under its own event so an
      # unreadable record is never mistaken for a real credential change.
      def watermark_state(account, verification)
        identifier = account[:external_id].to_s.empty? ? account[:email] : account[:external_id]
        customer   = Onetime::Customer.load_by_extid_or_email(identifier)

        unless customer
          Auth::Logging.log_auth_event(
            :sso_link_verification_watermark_probe_missing,
            level: :warn,
            provider: verification.provider,
            account_id: verification.account_id,
          )
          return :unreadable
        end

        if customer.last_password_update.to_i > verification.password_watermark.to_i
          :advanced
        else
          :unchanged
        end
      rescue StandardError => ex
        Auth::Logging.log_auth_event(
          :sso_link_verification_watermark_probe_error,
          level: :warn,
          provider: verification.provider,
          account_id: verification.account_id,
          error: ex.message,
        )
        :unreadable
      end

      # Mirror the after_login MFA decision (a pure function of the account's stored
      # factors, via_omniauth: false) so the bind is gated on FULL authentication.
      # When the OTP feature is not loaded (MFA off — the default) no second factor
      # can be pending, so this is false and the bind proceeds.
      def second_factor_pending?(account_id)
        return false unless @mfa_feature_loaded

        mfa_state = Auth::Operations::MfaStateChecker.new(@db).check(account_id)
        Auth::Operations::DetectMfaRequirement.call(
          account_id: account_id,
          has_otp_secret: mfa_state.has_otp_secret,
          has_recovery_codes: mfa_state.has_recovery_codes,
          via_omniauth: false,
        ).requires_mfa?
      end

      def expired
        Result.new(status: :link_expired, bound: false, second_factor_pending: false)
      end

      def conflict(verification)
        Auth::Logging.log_auth_event(
          :sso_link_verification_conflict,
          level: :warn,
          email: OT::Utils.obscure_email(verification.email),
          provider: verification.provider,
          account_id: verification.account_id,
        )
        Result.new(
          status: :link_conflict,
          account_id: verification.account_id,
          provider: verification.provider,
          bound: false,
          second_factor_pending: false,
        )
      end

      def invalidated(verification)
        Auth::Logging.log_auth_event(
          :sso_link_verification_invalidated,
          level: :warn,
          email: OT::Utils.obscure_email(verification.email),
          provider: verification.provider,
          account_id: verification.account_id,
        )
        Result.new(
          status: :link_invalidated,
          account_id: verification.account_id,
          provider: verification.provider,
          bound: false,
          second_factor_pending: false,
        )
      end

      # The watermark could not be READ (see watermark_state) — an infrastructure
      # failure, not a credential change. Rejected exactly like an advance (the
      # token is already spent, so this is terminal either way); only the status
      # differs, so the route can send copy that does not accuse the user of a
      # credential change they never made.
      #
      # No audit event here: watermark_state already logged the SPECIFIC shape
      # (:sso_link_verification_watermark_probe_missing / _probe_error) at :warn
      # with the reason attached. A second terminal event would double-count the
      # same failure with strictly less detail.
      def probe_failed(verification)
        Result.new(
          status: :link_error,
          account_id: verification.account_id,
          provider: verification.provider,
          bound: false,
          second_factor_pending: false,
        )
      end
    end
  end
end
