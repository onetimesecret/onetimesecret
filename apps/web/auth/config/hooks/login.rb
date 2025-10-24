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
      auth.after_login do
        OT.info "[auth] User logged in: #{account[:email]}"

        # Check if user is in partially authenticated state (has password but needs MFA)
        # Rodauth's two_factor_base provides this method automatically
        if two_factor_partially_authenticated?
          OT.info "[auth] MFA required for #{account[:email]}, deferring full session sync"
          # Only set minimal session data, full sync happens after MFA
          session['account_id'] = account_id
          session['email'] = account[:email]
          session['mfa_pending'] = true
        else
          OT.info "[auth] No MFA required or MFA completed, syncing session"
          Onetime::ErrorHandler.safe_execute('sync_session_after_login',
            account_id: account_id,
            email: account[:email],
          ) do
            Handlers.sync_session_after_login(account, account_id, session, request)
          end
        end
      end


      # Require second factor during login if user has MFA setup
      #
      # TODO: Fix this NoMethodError. It's the correct method name but
      # we're obviously not calling it the right way.
      #
      # auth.require_two_factor_authenticated do
      #   # Check if account has OTP configured
      #   db[otp_keys_table].where(otp_keys_id_column => account_id).count > 0
      # end

      # After successful password authentication, check for MFA
      auth.after_login do
        # If user has MFA enabled, don't mark as fully authenticated yet
        if db[otp_keys_table].where(otp_keys_id_column => account_id).count > 0
          # Set flag that second factor is required
          session[:awaiting_mfa] = true

          # For JSON mode, return different success message
          if json_request?
            json_response[:mfa_required] = true
            json_response[:mfa_auth_url] = "/#{otp_auth_route}"
            # Don't set authenticated_at yet
          end
        else
          # No MFA, proceed normally
          session[:awaiting_mfa] = false
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
