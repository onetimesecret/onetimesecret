# apps/web/auth/config/hooks/two_factor.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  # Owner of the two_factor_base completion hook.
  #
  # after_two_factor_authentication fires after ANY successful second factor
  # (OTP via otp-auth, recovery code via recovery-auth, passkey via
  # webauthn-auth — each ends in two_factor_authenticate(type)). It performs
  # the app-side completion of a two-factor login: session sync, clearing the
  # awaiting_mfa hand-off flag, the deferred SSO bind, and the sign-in alert.
  #
  # OWNERSHIP: this hook used to live in Hooks::MFA, which config.rb only
  # registers when AUTH_MFA_ENABLED=true. That stranded webauthn-only
  # deployments (AUTH_WEBAUTHN_ENABLED=true, AUTH_MFA_ENABLED=false): Rodauth's
  # POST /auth/webauthn-auth completed the second factor, but no app hook ran —
  # SyncSession never fired and session['awaiting_mfa'] stayed true, locking
  # the user out of every gated route. It now lives here, registered by
  # config.rb whenever ANY two-factor feature is loaded (mfa_enabled? OR
  # webauthn_enabled?), after the feature modules have enabled two_factor_base
  # so the hook method exists. One owner, per the invariant in
  # config/hooks.rb — Hooks::MFA keeps the OTP-specific hooks only.
  module TwoFactor
    def self.configure(auth)
      # ========================================================================
      # HOOK: After Successful Two-Factor Authentication
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after successful second-factor verification during
      # login (OTP code, recovery code, or WebAuthn passkey). It completes the
      # authentication flow and syncs the session.
      #
      # NOTE: This hook is provided by two_factor_base (enabled transitively by
      # BOTH the otp feature and the webauthn feature via `depends
      # :two_factor_base`). It fires after successful two-factor
      # authentication of any type.
      #
      auth.after_two_factor_authentication do
        correlation_id = session[:auth_correlation_id]

        # Calculate verification duration if we have start time
        duration_ms = if session[:mfa_verification_start]
                       start = session.delete(:mfa_verification_start)
                       ((Onetime.now_in_μs - start) / 1000.0).round(2)
                     end

        Auth::Logging.log_auth_event(
          :mfa_verification_success,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
          duration_ms: duration_ms,
          correlation_id: correlation_id,
        )

        # Measure and log session sync duration
        Auth::Logging.measure(:mfa_session_sync, account_id: account_id, correlation_id: correlation_id) do
          # Rodauth handles session management automatically, but we sync session data
          Onetime::ErrorHandler.safe_execute(
            'sync_session_after_mfa',
            account_id: account_id,
            email: account[:email],
          ) do
            Auth::Operations::SyncSession.call(
              account: account,
              account_id: account_id,
              session: session,
              request: request,
              correlation_id: correlation_id,
            )
          end
        end

        # Complete a DEFERRED SSO identity bind (#3877 / #3840 Phase 4.A). The
        # link-sso interstitial verifies the existing password but must NOT bind
        # the (provider, issuer, uid) identity while a second factor is pending
        # (SSO logins are MFA-exempt — a pre-2FA bind would be an MFA-bypassing
        # login path), so it stashes the authorized bind in a short-TTL
        # SessionSidecar key bound to the partial MFA session's sid (#3858).
        # The second factor has now succeeded — finish it. Single-use (atomic
        # GETDEL at the store), account-bound, and audit-and-skip on
        # conflict/mismatch: MFA already succeeded, so nothing here may fail
        # the login — hence the best-effort wrapper. :none for every login
        # that didn't come through the interstitial's deferred branch (the
        # common case: one Redis GETDEL, no DB access).
        Onetime::ErrorHandler.safe_execute('complete_deferred_sso_bind', account_id: account_id) do
          outcome = Auth::Operations::DeferredSsoBind.complete(
            db: db,
            sid: session.id&.public_id,
            account_id: account_id,
          )
          unless outcome == :none
            Auth::Logging.log_auth_event(
              :sso_deferred_bind_completed,
              level: outcome == :ok ? :info : :warn,
              log_metric: true,
              account_id: account_id,
              outcome: outcome,
              correlation_id: correlation_id,
            )
          end
        end

        # Best-effort new-sign-in security alert for MFA logins. The password
        # step's after_login deferred the alert (awaiting_mfa), so this is the
        # single alert for a two-factor login. Location is the country Otto's
        # IPPrivacyMiddleware resolved (env['otto.privacy.geo_country']),
        # falling back to the already-masked client IP — never the raw request
        # IP (#3989).
        Onetime::ErrorHandler.safe_execute('new_login_alert_email', account_id: account_id) do
          recipient = Onetime::Customer.find_by_email(account[:email])
          # Customers default locale to "" (matches Redis string load), which is
          # truthy and would slip past a bare `||`. Treat blank as missing.
          locale    = recipient&.locale
          locale    = OT.default_locale if locale.to_s.strip.empty?
          Onetime::Jobs::Publisher.enqueue_email(
            :new_login_alert,
            {
              email_address: account[:email],
              device_info: request.user_agent || 'Unknown device',
              location: Auth::Operations::ResolveLoginLocation.call(
                geo_country: request.env['otto.privacy.geo_country'],
                masked_ip: request.env['otto.client_ip'],
              ),
              login_at: Time.now.utc.iso8601,
              locale: locale,
            },
            fallback: :async_thread,
          )
        end

        # Log metric for MFA completion
        Auth::Logging.log_metric(
          :mfa_authentication_complete,
          value: 1,
          unit: :count,
          account_id: account_id,
          correlation_id: correlation_id,
        )

        # Write the healing FALSE over the hand-off flag.
        #
        # STRING key deliberately (#3854): it is the key PrepareMfaSession wrote,
        # and BaseSessionAuthStrategy enforces MFA by reading
        # session['awaiting_mfa'] — a symbol :awaiting_mfa would silently never
        # match. SyncSession above already deletes both key forms, but it runs
        # inside safe_execute and swallows errors, so on a sync failure this line
        # is the only remaining clear and it must target the string key or the
        # user stays locked in the awaiting-MFA state after completing MFA.
        #
        # FALSE rather than a delete (#3858): this is not parked state — the
        # sidecar commit treats a falsy awaiting_mfa as a DELETE
        # (absent_when_falsy), so on success this request converges the field to
        # absent everywhere. The write is load-bearing for exactly one failure
        # case: if this request's sidecar commit FAILS, the DEL of the stale
        # sidecar awaiting_mfa=true is lost with it — but write_session's rescue
        # keeps this false in the BLOB, where blob-wins outranks the stale true
        # on the next read and the next healthy commit heals it. A deletion here
        # could not win that conflict: the blob would carry nothing, and the
        # stale true would re-merge (and re-commit with a fresh TTL) on every
        # request — an authenticated session locked out of every gated route
        # indefinitely.
        session['awaiting_mfa'] = false

        # Clean up correlation ID after successful completion
        session.delete(:auth_correlation_id)

        # Billing redirect: add plan selection to JSON response (issue #3275).
        # Billing.configure defines add_billing_redirect_to_response via auth_class_eval,
        # so the method is only available when billing is enabled. Check respond_to?
        # to avoid NoMethodError when billing is disabled (self-hosted).
        if json_request? && respond_to?(:add_billing_redirect_to_response)
          add_billing_redirect_to_response
        end
      end
    end
  end
end
