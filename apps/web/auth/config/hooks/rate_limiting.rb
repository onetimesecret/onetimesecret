# frozen_string_literal: true

#
# apps/web/auth/config/hooks/rate_limiting.rb
#
# This file defines the Rodauth hooks for implementing rate limiting on
# authentication attempts. It helps prevent brute-force attacks by
# tracking and limiting login attempts.
#

module Auth
  module Config
    module Hooks
      module RateLimiting
        #
        # Configuration
        #
        # This method returns a proc that Rodauth will execute to configure the
        # rate limiting hooks.
        #
        def self.configure
          proc do
            #
            # Hook: Before Login Attempt
            #
            # This hook is triggered before processing a login attempt. It implements
            # a rate limit of 5 attempts per 5 minutes for a given email address.
            #
            before_login_attempt do
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
            # Hook: After Login Failure
            #
            # This hook is triggered after a login attempt fails. It logs the
            # failure and raises a security alert on repeated failures.
            #
            after_login_failure do
              email = param('login') || param('email')
              ip    = request.ip

              rate_limit_key = "login_attempts:#{email}"
              client         = Familia.dbclient
              attempts       = client.get(rate_limit_key).to_i

              OT.info "[auth] Failed login attempt #{attempts}/5 for #{OT::Utils.obscure_email(email)} from #{ip}"

              # On the 4th (and subsequent) failed attempts, log a high-priority
              # security event to alert on potential brute-force activity.
              if attempts >= 4
                OT.le "[security] Potential brute force attack: #{attempts} failed attempts for #{OT::Utils.obscure_email(email)} from #{ip}"
              end
            end
          end
        end
      end
    end
  end
end
