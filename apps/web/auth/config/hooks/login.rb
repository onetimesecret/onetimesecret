# apps/web/auth/config/hooks/login.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  module Login
    # Pick the completion ROUTE (no mount prefix) for an MFA-required JSON
    # response. OTP keeps precedence when configured (established UX; the
    # otp-auth page also hosts recovery-code entry, which is why the
    # recovery-codes-only fallthrough lands there too). The webauthn route is
    # chosen whenever a passkey is available and OTP is not — INCLUDING the
    # common [:webauthn, :recovery_codes] shape (recovery codes are
    # auto-minted on passkey registration when AUTH_MFA_ENABLED=true, via
    # Rodauth's add_webauthn_credential + auto_add_recovery_codes?), where an
    # OTP URL would point at a factor the account cannot satisfy.
    #
    # The after_login caller gates each factor on its feature being loaded, so
    # the route argument matching the returned branch is always non-nil there.
    # Module function (not hook-closure logic) so it is unit-testable.
    #
    # @param decision [Auth::Operations::DetectMfaRequirement::Decision]
    # @param otp_route [String, nil] otp_auth_route when the OTP feature is loaded
    # @param webauthn_route [String, nil] webauthn_auth_route when webauthn is loaded
    # @return [String] the route segment to append to the auth mount prefix
    def self.mfa_auth_route(decision, otp_route:, webauthn_route:)
      return otp_route if decision.has_otp?
      return webauthn_route if decision.has_webauthn?

      otp_route # recovery-codes-only: entry lives on the OTP verify page
    end

    def self.configure(auth) # rubocop:disable Metrics/PerceivedComplexity
      #
      # Hook: Before Login Attempt
      #
      # This hook is triggered before processing a login attempt. It generates
      # a correlation ID for tracking the entire authentication flow.
      #
      # NOTE: Rodauth hooks don't chain — each call overwrites the previous
      # definition. All before_login_attempt logic must live here, not split
      # across hook files. billing.rb's capture_plan_selection was moved here
      # after the hook-collision bug (#3275).
      #
      auth.before_login_attempt do
        # Billing: capture plan selection from query params before validation.
        # Method defined by Billing.configure via auth_class_eval; no-op if billing disabled.
        capture_plan_selection if respond_to?(:capture_plan_selection)

        email = param_or_nil('login') || param_or_nil('email')

        # Generate correlation ID for this authentication attempt
        correlation_id                = Auth::Logging.generate_correlation_id
        session[:auth_correlation_id] = correlation_id

        Auth::Logging.log_auth_event(
          :login_attempt,
          level: :info,
          email: OT::Utils.obscure_email(email),
          ip: request.ip,
          correlation_id: correlation_id,
        )
      end

      #
      # Hook: After Login
      #
      # This hook is triggered after a user successfully authenticates. It's
      # the primary integration point for syncing the application session.
      #
      # After successful authentication (password OR passwordless), check MFA requirement
      # BEFORE syncing session to prevent granting full access prematurely.
      #
      # SECURITY FLOW:
      # 1. Query database for MFA configuration state (MfaStateChecker)
      # 2. Make MFA requirement decision with primitive data (DetectMfaRequirement)
      # 3. Either prepare session for MFA flow OR sync full session
      #
      auth.after_login do
        # INTERNAL REQUESTS ARE NOT LOGINS. `Auth::Config.valid_login_and_password?`
        # (account destroy, change email, change password, /auth/link-sso) is a
        # Rodauth internal request: it runs the real login route to check a
        # password, then throws the result away. It has no web session — Rodauth
        # hands the internal instance a bare Hash — and no user-visible sign-in
        # happened, so every side effect below is wrong for it:
        #   - `session.id` raises NoMethodError on a Hash (BACKEND-B0/B1/B3/B4,
        #     one Sentry issue per confirmation endpoint);
        #   - a password CONFIRMATION was logging `login_success` into the auth
        #     audit stream and could fire the new-sign-in security alert;
        #   - SyncSession and the deferred SSO bind would act on a session that
        #     is discarded microseconds later.
        # The real logins that need this hook are real requests: /auth/link-sso
        # verifies with the internal request but establishes the session with its
        # own `rodauth.login('password')` on the actual route.
        #
        # respond_to? takes the include_all argument because internal_request?
        # is PRIVATE on the Rodauth instance; the one-argument form returns
        # false for it and the guard would never fire. The feature is enabled
        # unconditionally today (config/base.rb), so the guard is for a future
        # conditional enablement — same defensive shape as
        # hooks/create_account.rb.
        next if respond_to?(:internal_request?, true) && internal_request?

        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :login_success,
          level: :info,
          account_id: account_id,
          email: OT::Utils.obscure_email(account[:email]),
          correlation_id: correlation_id,
        )

        # Detect SSO callback context. omniauth_provider is defined by
        # rodauth-omniauth when the omniauth feature is enabled; it returns a
        # truthy value (e.g. 'oidc') only when this login originated from an
        # OmniAuth callback. For password logins it is nil or absent.
        via_omniauth = respond_to?(:omniauth_provider) && !omniauth_provider.to_s.empty?

        # Stamp how this session authenticated, ONCE, at auth time. Rodauth's
        # login(auth_type) sets authenticated_by = [auth_type] immediately before
        # this hook fires, so authenticated_by.first is the PRIMARY login method:
        # 'password', 'email_auth' (magic link), 'webauthn', or 'omniauth'. This is
        # the only point where the mechanism is reliably known — downstream (e.g.
        # Session#write_session) cannot re-derive it (the omniauth markers are
        # deleted later in the callback, and password/magic-link/webauthn leave no
        # trace in session_data). The value persists in the encrypted session and
        # is copied verbatim into the SessionMetadata sidecar (spec
        # docs/specs/colonel-ui/40-*). Second factors (otp, webauthn-as-2FA) append
        # to authenticated_by later via after_two_factor_authentication; the sidecar
        # tracks those separately as mfa_used, so first == primary is what we want.
        # String key matches the app-session convention written by SyncSession.
        primary_auth           = authenticated_by.first if respond_to?(:authenticated_by)
        session['auth_method'] = primary_auth || (via_omniauth ? 'omniauth' : 'password')

        # Join domain organization for SSO logins on custom domains.
        # Runs BEFORE MFA detection so SSO users with OTP configured (e.g.,
        # legacy password+MFA accounts now using SSO) still get joined. This
        # is also the single point of cleanup for :validated_omniauth_domain_id:
        # whether or not the join happens, the key is consumed here.
        # New accounts have already been joined by after_omniauth_create_account
        # (which consumed the key); for them, session.delete returns nil and
        # the guard below short-circuits — no duplicate call.
        domain_id = session.delete(:validated_omniauth_domain_id)
        if domain_id
          customer = Onetime::Customer.find_by_extid(account[:external_id])
          if customer
            result = Onetime::ErrorHandler.safe_execute(
              'join_domain_organization_login',
              account_id: account_id,
              domain_id: domain_id,
            ) do
              Auth::Operations::JoinDomainOrganization.new(
                customer: customer,
                domain_id: domain_id,
              ).call
            end

            # Clear org cache so next request picks up the domain org
            # OrganizationLoader caches in session with key "org_context:#{customer.objid}"
            if result&.dig(:joined)
              cache_key = "org_context:#{customer.objid}"
              session.delete(cache_key)
              OT.ld "[after_login] Cleared org cache for #{customer.custid} after domain org join"
            end
          end
        end

        # MFA detection: run when ANY second-factor feature is loaded. The OTP
        # methods exist only when AUTH_MFA_ENABLED=true (config.rb); the
        # webauthn methods only when AUTH_WEBAUTHN_ENABLED=true. WebAuthn is a
        # second factor in its own right (the webauthn feature transitively
        # enables two_factor_base), so a webauthn-only deployment must reach
        # this branch too — everything below stays nil-safe for the
        # missing-OTP case (otp_auth_route is only called when an OTP-family
        # method is among the decision's methods).
        mfa_decision = nil

        otp_loaded      = respond_to?(:otp_auth_route)
        recovery_loaded = respond_to?(:recovery_auth_route)
        webauthn_loaded = respond_to?(:webauthn_auth_route)

        # Was the FIRST factor of this login a passkey? POST /auth/webauthn-login
        # calls login('webauthn'), whose login_session sets authenticated_by to
        # ['webauthn'] immediately before this hook fires (gem webauthn_login.rb;
        # with webauthn_login_user_verification_additional_factor? it may already
        # be ['webauthn', 'webauthn-verification']). Second-factor webauthn
        # completion appends to authenticated_by via two_factor_authenticate
        # WITHOUT re-firing after_login, so 'webauthn' here can only mean the
        # PRIMARY credential of this very login.
        webauthn_first_factor = !!(respond_to?(:authenticated_by) &&
                                   authenticated_by&.include?('webauthn'))

        # Align Rodauth's own two-factor state with the policy that a passkey
        # login is FULLY authenticated. Without this, an account that also has a
        # password/OTP (possible_authentication_methods >= 2) is left
        # two_factor_partially_authenticated? after a passkey login, and
        # Rodauth-internal routes (change-password, webauthn-setup, ...) wall it
        # behind a second factor it may be unable to complete — webauthn-auth
        # rejects re-use of the login type. This mirrors what Rodauth itself does
        # natively when webauthn_login_user_verification_additional_factor? is on
        # and the authenticator reported user verification (same auth type
        # string, same session keys); we extend it to the non-UV residual case
        # deliberately: possession + local gesture is the accepted bar.
        if webauthn_first_factor && !two_factor_authenticated? && uses_two_factor_authentication?
          two_factor_update_session('webauthn-verification')
        end

        if otp_loaded || webauthn_loaded
          # Step 1: Check MFA configuration state from database.
          # Queries account_otp_keys, account_recovery_codes, and
          # account_webauthn_keys directly — the tables exist in the migration
          # regardless of which features are loaded, so this is always safe.
          mfa_state = Auth::Operations::MfaStateChecker.new(db).check(account_id)

          # Only count factors whose completion route is actually loaded: a
          # factor the user cannot complete must never gate the login. OTP
          # rows with AUTH_MFA_ENABLED=false get the same no-MFA outcome as
          # before (when this branch was skipped entirely); webauthn rows with
          # AUTH_WEBAUTHN_ENABLED=false likewise do not gate.
          has_otp      = otp_loaded && mfa_state.has_otp_secret
          has_recovery = recovery_loaded && mfa_state.has_recovery_codes
          has_webauthn = webauthn_loaded && mfa_state.has_webauthn

          Auth::Logging.log_auth_event(
            :mfa_state_checked,
            level: :debug,
            account_id: account_id,
            has_otp: mfa_state.has_otp_secret,
            has_recovery: mfa_state.has_recovery_codes,
            has_webauthn: mfa_state.has_webauthn,
            mfa_enabled: mfa_state.mfa_enabled?,
            via_omniauth: via_omniauth,
            via_webauthn_login: webauthn_first_factor,
            correlation_id: correlation_id,
          )

          # Step 2: Make MFA requirement decision (pure function, no side effects)
          # This accepts only primitive data and returns an immutable decision object.
          # SSO logins (via_omniauth: true) bypass MFA — the IdP is trusted to
          # handle authentication factors. Passkey-first logins
          # (via_webauthn_login: true) bypass MFA — the credential just used IS
          # a second factor, and re-demanding it would loop (see the op's doc).
          mfa_decision = Auth::Operations::DetectMfaRequirement.call(
            account_id: account_id,
            has_otp_secret: has_otp,
            has_recovery_codes: has_recovery,
            has_webauthn: has_webauthn,
            via_omniauth: via_omniauth,
            via_webauthn_login: webauthn_first_factor,
          )
        end

        if mfa_decision&.requires_mfa?
          # Step 3a: MFA required - prepare session for MFA flow
          Auth::Logging.log_auth_event(
            :mfa_required,
            level: :info,
            account_id: mfa_decision.account_id,
            email: account[:email],
            mfa_methods: mfa_decision.mfa_methods,
            reason: mfa_decision.reason,
            correlation_id: correlation_id,
            note: 'Deferring full session sync until after second factor',
          )

          # Prepare minimal session for MFA verification flow
          Auth::Operations::PrepareMfaSession.call(
            session: session,
            account_id: account_id,
            email: account[:email],
            external_id: account[:external_id],
            correlation_id: correlation_id,
          )

          # For JSON mode, indicate MFA is required and provide auth URL.
          # Route selection lives in Login.mfa_auth_route (unit-tested): OTP
          # keeps precedence when configured; webauthn wins otherwise — even
          # combined with auto-minted recovery codes. The URL is prefixed with
          # the app's mount point (SCRIPT_NAME, '/auth' via the registry's
          # Rack::URLMap) so the client receives a request-able path, not a
          # bare route segment. (The SPA currently routes to /mfa-verify
          # itself and ignores this field — keep it truthful anyway.)
          if json_request?
            mfa_route = Auth::Config::Hooks::Login.mfa_auth_route(
              mfa_decision,
              otp_route: otp_loaded ? otp_auth_route : nil,
              webauthn_route: webauthn_loaded ? webauthn_auth_route : nil,
            )

            json_response[:mfa_required] = true
            json_response[:mfa_auth_url] = "#{request.script_name}/#{mfa_route}"
            json_response[:mfa_methods]  = mfa_decision.mfa_methods

            Auth::Logging.log_auth_event(
              :mfa_json_response,
              level: :debug,
              account_id: mfa_decision.account_id,
              email: account[:email],
              correlation_id: correlation_id,
              json_response_keys: json_response.keys,
            )
          end
        else
          # Step 3b: No MFA required - proceed with full session sync
          Auth::Logging.log_auth_event(
            :session_sync_start,
            level: :info,
            account_id: account_id,
            external_id: account[:external_id],
            reason: mfa_decision&.reason || 'mfa_not_loaded',
            correlation_id: correlation_id,
            note: 'No MFA required',
          )
          session['awaiting_mfa'] = false

          # Self-heal a DEFERRED SSO bind whose MFA prediction went stale
          # (#3877). The link-sso interstitial stashes a deferred bind (a
          # sid-bound SessionSidecar key written in the rodauth.login block,
          # i.e. BEFORE this hook — #3858) only when its pre-login MFA check
          # said a second factor was pending. If the decision just made HERE
          # disagrees (the account's factors changed in the window between the
          # two checks), no second factor will ever fire to complete the stash
          # — so complete it now: the password verified moments ago and no
          # factor is pending, which is exactly the authorization the
          # interstitial's direct-bind branch requires. For every other login
          # the stash cannot exist (login_session re-keyed the sid before this
          # hook, and sidecar keys are sid-bound) and this is a no-op (:none).
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

          Onetime::ErrorHandler.safe_execute(
            'sync_session_after_login',
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

          # Best-effort new-sign-in security alert for password-only logins.
          # MFA logins fire this from after_two_factor_authentication instead,
          # so each completed login produces exactly one alert. Location is the
          # country Otto's IPPrivacyMiddleware resolved
          # (env['otto.privacy.geo_country']), falling back to the already-masked
          # client IP — never the raw request IP (#3989).
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

          # Invitation acceptance is intentionally not performed here. The
          # frontend issues an explicit POST /api/invite/:token/accept after
          # login completes, giving a single acceptance code path regardless
          # of whether the user signed up fresh or already had an account.
        end

        # Billing redirect: add plan selection to JSON response (issue #3275).
        # Billing.configure defines add_billing_redirect_to_response via auth_class_eval,
        # so the method is only available when billing is enabled. Check respond_to?
        # to avoid NoMethodError when billing is disabled (self-hosted).
        if json_request? && respond_to?(:add_billing_redirect_to_response)
          add_billing_redirect_to_response
        end
      end

      #
      # Hook: After Login Failure
      #
      # This hook is triggered after a login attempt fails. Rodauth handles
      # rate limiting via the lockout feature, so we just log the failure.
      #
      auth.after_login_failure do
        email          = param_or_nil('login') || param_or_nil('email')
        correlation_id = session[:auth_correlation_id]

        # Check if this might be an empty auth database scenario
        # Rodauth's login_failure doesn't distinguish between "account not found"
        # and "wrong password", so we check the accounts table
        account_count = nil
        begin
          account_count = db[:accounts].count
        rescue StandardError => ex
          OT.debug "[auth] Could not check account count: #{ex.message}"
        end

        if account_count&.zero?
          diagnostic_hint = <<~HINT.strip
            Login failed and auth database has 0 accounts. This typically occurs in
            worktree/multi-instance dev setups with empty SQLite. Consider: (1) seeding
            accounts table from another instance, (2) creating a new account via signup,
            or (3) using a shared database for auth data.
          HINT

          Auth::Logging.log_auth_event(
            :login_failure_empty_database,
            level: :error,
            email: OT::Utils.obscure_email(email),
            ip: request.ip,
            correlation_id: correlation_id,
            diagnostic_hint: diagnostic_hint,
          )
        else
          Auth::Logging.log_auth_event(
            :login_failure,
            level: :warn,
            email: OT::Utils.obscure_email(email),
            ip: request.ip,
            correlation_id: correlation_id,
          )
        end
      end
    end
  end
end
