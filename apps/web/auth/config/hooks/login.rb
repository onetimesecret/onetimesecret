# apps/web/auth/config/hooks/login.rb

module Auth::Config::Hooks
  module Login
    def self.configure(auth)
      #
      # Hook: Before Login Attempt
      #
      # This hook is triggered before processing a login attempt. It generates
      # a correlation ID for tracking the entire authentication flow.
      #
      auth.before_login_attempt do
        email = param('login') || param('email')

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
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :login_success,
          level: :info,
          account_id: account_id,
          email: OT::Utils.obscure_email(account[:email]),
          correlation_id: correlation_id,
        )

        # Step 1: Check MFA configuration state from database
        # This queries the database directly for account_otp_keys and account_recovery_codes
        mfa_state = Auth::Operations::MfaStateChecker.new(db).check(account_id)

        Auth::Logging.log_auth_event(
          :mfa_state_checked,
          level: :debug,
          account_id: account_id,
          has_otp: mfa_state.has_otp_secret,
          has_recovery: mfa_state.has_recovery_codes,
          mfa_enabled: mfa_state.mfa_enabled?,
          correlation_id: correlation_id,
        )

        # Step 2: Make MFA requirement decision (pure function, no side effects)
        # This accepts only primitive data and returns an immutable decision object
        mfa_decision = Auth::Operations::DetectMfaRequirement.call(
          account_id: account_id,
          has_otp_secret: mfa_state.has_otp_secret,
          has_recovery_codes: mfa_state.has_recovery_codes
        )

        if mfa_decision.requires_mfa?
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
            correlation_id: correlation_id
          )

          # For JSON mode, indicate MFA is required and provide auth URL
          if json_request?
            json_response[:mfa_required]  = true
            json_response[:mfa_auth_url] = "/#{otp_auth_route}"
            json_response[:mfa_methods] = mfa_decision.mfa_methods

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
            account_id: mfa_decision.account_id,
            external_id: account[:external_id],
            reason: mfa_decision.reason,
            correlation_id: correlation_id,
            note: 'No MFA required',
          )
          session['awaiting_mfa'] = false

          Onetime::ErrorHandler.safe_execute('sync_session_after_login',
            account_id: account_id,
            external_id: account[:external_id],
          ) do
            Auth::Operations::SyncSession.call(
              account: account,
              account_id: account_id,
              session: session,
              request: request,
              correlation_id: correlation_id
            )
          end
        end
      end

      #
      # Hook: After Login Failure
      #
      # This hook is triggered after a login attempt fails. Rodauth handles
      # rate limiting via the lockout feature, so we just log the failure.
      #
      auth.after_login_failure do
        email          = param('login') || param('email')
        correlation_id = session[:auth_correlation_id]

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
