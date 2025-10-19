# apps/web/auth/config/hooks/rate_limiting.rb

module Auth::Config::Hooks::RateLimiting
  def self.configure
    proc do
      # Rate limiting: 5 login attempts per 5 minutes
      before_login_attempt do
        email = param('login') || param('email')

        # Log login attempt
        OT.li "[auth] Login attempt: #{OT::Utils.obscure_email(email)}"

        rate_limit_key = "login_attempts:#{email}"

        client = Familia.dbclient
        attempts = client.incr(rate_limit_key).to_i

        # Set expiry on first attempt (5 minute window)
        client.expire(rate_limit_key, 300) if attempts == 1

        # Allow 5 attempts per 5 minutes
        if attempts > 5
          remaining_ttl = client.ttl(rate_limit_key)
          minutes = (remaining_ttl / 60.0).ceil

          OT.info "[auth] Rate limit exceeded for #{OT::Utils.obscure_email(email)}: #{attempts} attempts"
          throw_error_status(429, 'login', "Too many login attempts. Please try again in #{minutes} minute#{'s' if minutes != 1}.")
        end
      end

      # Track failed login attempts for security monitoring
      after_login_failure do
        email = param('login') || param('email')
        ip = request.ip

        rate_limit_key = "login_attempts:#{email}"
        client = Familia.dbclient
        attempts = client.get(rate_limit_key).to_i

        OT.info "[auth] Failed login attempt #{attempts}/5 for #{OT::Utils.obscure_email(email)} from #{ip}"

        # Alert on potential brute force (4th failed attempt)
        if attempts >= 4
          OT.le "[security] Potential brute force attack: #{attempts} failed attempts for #{OT::Utils.obscure_email(email)} from #{ip}"
        end
      end
    end
  end
end
