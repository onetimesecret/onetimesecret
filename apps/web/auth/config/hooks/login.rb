# apps/web/auth/config/hooks/login.rb

module Auth::Config::Hooks
  module Login
    def self.configure(auth)


      #
      # Hook: Before Login Attempt
      #
      # This hook is triggered before processing a login attempt. It implements
      # a rate limit of 5 attempts per 5 minutes for a given email address.
      #
      auth.before_login_attempt do
        email = param('login') || param('email')

        OT.info "[auth] Login attempt: #{OT::Utils.obscure_email(email)}"

        rate_limit_key = "login_attempts:#{email}"
        client         = Familia.dbclient

        # Increment the attempt counter for this email.
        attempts = client.incr(rate_limit_key).to_i

        # On the first attempt in a new window, set a 5-minute expiry.
        client.expire(rate_limit_key, 300) if attempts == 1

        # If attempts exceed the limit, block the request.
        if attempts > 5
          remaining_ttl = client.ttl(rate_limit_key)
          minutes       = (remaining_ttl / 60.0).ceil
          pluralize     = minutes == 1 ? '' : 's'

          OT.info "[auth] Rate limit exceeded for #{OT::Utils.obscure_email(email)}: #{attempts} attempts"
          throw_error_status(429, 'login', "Too many login attempts. Please try again in #{minutes} minute#{pluralize}.")
        end
      end

      #
      # Hook: After Login
      #
      # This hook is triggered after a user successfully authenticates. It's
      # the primary integration point for syncing the application session.
      #
      # After successful authentication (password OR passwordless), check MFA requirement
      # BEFORE syncing session to prevent granting full access prematurely
      auth.after_login do
        OT.info "[auth] User logged in: #{account[:email]}"

        # Use Rodauth's built-in method to check if MFA is required for this user.
        #
        # NOTE: The subtle (yet not so subtle) difference between the two methods:
        # `uses_two_factor_authentication?` -> Whether the account for the
        # current session has setup two factor authentication.
        #
        # `two_factor_partially_authenticated?` -> Returns true if the session
        # is logged in, the account has setup two factor authentication,
        # but has not yet authenticated with a second factor.
        #
        if uses_two_factor_authentication?
          # MFA required - defer full session sync until after second factor
          OT.info "[auth] MFA required for #{account[:email]}, deferring full session sync"

          # Set minimal session data for MFA flow
          session[:awaiting_mfa] = true
          session['account_id'] = account_id
          session['email'] = account[:email]

          # Store external_id so frontend can display user email during MFA
          # (but user won't have full access until MFA complete)
          if account[:external_id]
            session['external_id'] = account[:external_id]
          end

          # For JSON mode, indicate MFA is required
          if json_request?
            json_response[:mfa_required] = true
            json_response[:mfa_auth_url] = "/#{otp_auth_route}"
          end
        else
          # No MFA required - proceed with full session sync
          OT.info "[auth] No MFA required, syncing session"
          session[:awaiting_mfa] = false

          Onetime::ErrorHandler.safe_execute('sync_session_after_login',
            account_id: account_id,
            email: account[:email],
          ) do
            Handlers.sync_session_after_login(account, account_id, session, request)
          end
        end
      end

      #
      # Hook: After Login Failure
      #
      # This hook is triggered after a login attempt fails. It logs the
      # failure and raises a security alert on repeated failures.
      #
      auth.after_login_failure do
        email = param('login') || param('email')
        ip    = request.ip

        rate_limit_key = "login_attempts:#{email}"
        client         = Familia.dbclient
        attempts       = client.get(rate_limit_key).to_i

        OT.info "[auth] Failed login attempt #{attempts}/5 for #{OT::Utils.obscure_email(email)} from #{ip}"

        # On the 4th (and subsequent) failed attempts, log a high-priority
        # security event to alert on potential brute-force activity.
        if attempts >= 4
          SemanticLogger['Auth'].error "Potential brute force attack detected on login endpoint",
            attempts: attempts,
            email: OT::Utils.obscure_email(email),
            ip: ip,
            threshold: 4
        end
      end

    end
  end
end
