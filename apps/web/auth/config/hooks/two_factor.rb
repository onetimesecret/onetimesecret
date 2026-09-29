# apps/web/auth/config/hooks/two_factor.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  # Owner of the two_factor_base completion hook.
  #
  # after_two_factor_authentication fires after ANY successful second factor
  # (OTP via otp-auth, recovery code via recovery-auth, passkey via
  # webauthn-auth — each ends in two_factor_authenticate(type)). It performs
  # the app-side completion of a two-factor login: session sync, the deferred
  # SSO bind, the session-id rotation (#4466), the sign-in alert, and clearing
  # the awaiting_mfa hand-off flag.
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
            external_id: account[:external_id],
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

        # Rotate the session id (#4466, RISK-2026-09-19-02). Rodauth renews the
        # id at the password step (login_session -> clear_session ->
        # session.destroy, config/base.rb) and not here; the second factor is
        # the privilege transition that turns an MFA-pending session into an
        # authenticated one, so it gets a fresh id too. Onetime::SessionRotation
        # destroys the old id through the store (SessionEnded marker, blob,
        # sidecar keys, metadata record) and writes the session data back under
        # the new id in this request; the response sets the new cookie.
        #
        # ORDER. After the deferred SSO bind above: its stash is a sidecar key
        # bound to the OLD id and is consumed there (GETDEL). After SyncSession:
        # the data it wrote is what crosses. Before RecentReauth.record and
        # remember_me_after_two_factor below: the proof is a sidecar key and the
        # remember stamp sizes the blob, and both must belong to the NEW id.
        #
        # PRESERVED, because it is in the session hash the rotation carries:
        #   - account_id, authenticated, authenticated_at, external_id, email,
        #     role (SyncSession), Rodauth's authenticated_by;
        #   - the active-session token and its join key active_session_id_hmac
        #     (config/features/active_sessions.rb): the row in
        #     account_active_session_keys is keyed by that digest, not by the
        #     Rack id, so the row survives and the remember stamp below finds it;
        #   - the surface marker (Onetime::SessionSurface::KEY): login_session
        #     stamped the surface the password step was served on
        #     (config/overrides/surface_binding.rb) and Auth::SessionRecheck
        #     refused a challenge replayed on another surface before this hook
        #     could run (session_recheck.rb), so the marker describes this
        #     request's surface and is kept;
        #   - the CSRF token: a rotation is not a sign-out, and
        #     Onetime::Middleware::CsrfResponseHeader returns a masked token on
        #     every response anyway, so the client is never left with a stale
        #     one;
        #   - remember_me_pending, consumed below.
        # CLEARED, on purpose:
        #   - awaiting_mfa on the old id: named as `completed:` so the store's
        #     stranded-hand-off warning stays quiet; the healing FALSE below
        #     converges the field to absent under the new id;
        #   - elevated_until: SyncSession already deleted it (#4327);
        #   - the old id's recent_reauth proof, if any: a fresh one is recorded
        #     below under the new id, or none when the primary was not local;
        #   - the snapshot version counter: ADR-046 scopes the epoch to one
        #     session id, and the epoch is derived per request, so the next
        #     snapshot starts a new stream. The SPA asks for it as an
        #     authentication mutation (MfaChallenge -> ensureAuthenticated ->
        #     authStore.setAuthenticated -> refresh kind 'auth-mutation'), which
        #     classifySnapshot applies as 'new-epoch' (src/utils/
        #     snapshotOrdering.ts) with no forced page load.
        #
        # FAILURE: fail closed. An incomplete rotation could leave the old id
        # readable without its awaiting_mfa key (the store's destroy keeps the
        # blob but purges the sidecars when the ended marker cannot be
        # written), and a Rodauth-logged-in blob without that key is what the
        # /auth router serves as an autologin session (Auth::SessionRecheck).
        # Onetime::SessionRotation writes the marker before touching anything
        # and puts the key back if the blob survives, but the login must not
        # continue on a session it could not end either: the hash is cleared
        # (the commit then writes an anonymous session under whichever id the
        # request ends with) and the error propagates to the router's error
        # handler, the same treatment the active-session join-key stamp gives
        # a login it cannot make revocable (config/features/active_sessions.rb).
        # The user signs in again. A nil result is a session with no
        # server-side id (a bare Hash, internal requests and some specs):
        # nothing to rotate and nothing left behind, so the login continues.
        begin
          rotation = Onetime::SessionRotation.rotate!(session, completed: ['awaiting_mfa'])
          if rotation.nil?
            Auth::Logging.log_auth_event(
              :session_rotation_skipped,
              level: :warn,
              account_id: account_id,
              reason: 'no server-side session id to rotate',
              correlation_id: correlation_id,
            )
          elsif rotation.complete
            Auth::Logging.log_auth_event(
              :session_rotated,
              level: :info,
              account_id: account_id,
              reason: 'mfa_completed',
              session_id: rotation.new_sid,
              previous_session_handle: Onetime::SessionEnded.handle_for(rotation.old_sid),
              correlation_id: correlation_id,
            )
          else
            raise Onetime::SessionRotation::Incomplete,
              "session id rotation incomplete (#{rotation.reason}); login refused"
          end
        rescue StandardError => ex
          session.clear
          Auth::Logging.log_auth_event(
            :session_rotation_FAILED,
            level: :error,
            account_id: account_id,
            error: ex.message,
            error_class: ex.class.name,
            correlation_id: correlation_id,
            security_warning: 'second factor completed but the old session id could not be ended; session cleared and login refused',
          )
          raise
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

        # Recent full re-authentication (#4410). The second factor just
        # completed on top of the primary credential from after_login, so
        # this is the completion of a full local ceremony — EXCEPT when the
        # primary was not an explicit local credential: a magic link
        # (email_auth) or an SSO callback (omniauth) is not local proof, and a
        # session minted by a path that never fires after_login (the
        # autologins, which call login_session directly) has no auth_method
        # at all. An allowlist of local primaries refuses all of those; a
        # denylist would turn an unknown primary + OTP into a false full
        # proof. (Rodauth's remember feature is not enabled, so there is no
        # remember restoration to consider here; remember-me extends the
        # session itself, Onetime::RememberMe, lib/onetime/session/remember_me.rb.)
        primary_auth = session['auth_method']
        if Onetime::RecentReauth::LOCAL_PRIMARIES.include?(primary_auth)
          Onetime::RecentReauth.record(
            session,
            request.env,
            account_id: account_id,
            methods: (respond_to?(:authenticated_by) ? Array(authenticated_by) : [primary_auth].compact),
          )
        end

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

        # Remember me, when the password step asked for it
        # (features/remember_me.rb). The 14 days run from here.
        remember_me_after_two_factor if respond_to?(:remember_me_after_two_factor)

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
