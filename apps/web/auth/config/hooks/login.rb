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
          email: email,
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
      # BEFORE syncing session to prevent granting full access prematurely
      #
      # two_factor_partially_authenticated? :: (two_factor_base feature) Returns true if
      #                                        the session is logged in, the account has
      #                                        setup two factor authentication, but has
      #                                        not yet authenticated with a second factor.
      # uses_two_factor_authentication? :: (two_factor_base feature) Whether the account
      #                                    for the current session has setup two factor
      #                                    authentication.
      # update_last_activity :: (account_expiration feature) Update the last activity
      #                         time for the current account.  Only makes sense to use
      #                         this if you are expiring accounts based on last activity.
      auth.after_login do
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :login_success,
          level: :info,
          account_id: account_id,
          email: account[:email],
          correlation_id: correlation_id,
        )

        # Detect MFA requirement using dedicated operation
        mfa_decision = Auth::Operations::DetectMfaRequirement.call(
          account: account,
          session: session,
          rodauth: self
        )

        if mfa_decision.requires_mfa?
          # MFA required - defer full session sync until after second factor
          Auth::Logging.log_auth_event(
            :mfa_required,
            level: :info,
            account_id: mfa_decision.account_id,
            email: mfa_decision.email,
            correlation_id: correlation_id,
            note: 'Deferring full session sync until after second factor',
          )

          # Set minimal session data for MFA flow
          session[:awaiting_mfa] = true
          session['account_id']   = mfa_decision.account_id
          session['email']        = mfa_decision.email

          # Store external_id so frontend can display user email during MFA
          if mfa_decision.external_id
            session['external_id'] = mfa_decision.external_id
          end

          # For JSON mode, indicate MFA is required
          if json_request?
            json_response[:mfa_required]  = true
            json_response[:mfa_auth_url] = "/#{otp_auth_route}"

            Auth::Logging.log_auth_event(
              :mfa_json_response,
              level: :debug,
              account_id: mfa_decision.account_id,
              email: mfa_decision.email,
              correlation_id: correlation_id,
              json_response_keys: json_response.keys,
            )
          end
        else
          # No MFA required - proceed with full session sync
          Auth::Logging.log_auth_event(
            :session_sync_start,
            level: :info,
            account_id: mfa_decision.account_id,
            email: mfa_decision.email,
            correlation_id: correlation_id,
            note: 'No MFA required',
          )
          session[:awaiting_mfa] = false

          Onetime::ErrorHandler.safe_execute('sync_session_after_login',
            account_id: account_id,
            email: account[:email],
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
          email: email,
          ip: request.ip,
          correlation_id: correlation_id,
        )
      end
    end
  end
end
