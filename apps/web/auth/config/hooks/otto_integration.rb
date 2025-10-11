# apps/web/auth/config/hooks/otto_integration.rb

module Auth
  module Config
    module Hooks
      module OttoIntegration
        def self.configure
          proc do
            # Clear rate limit and sync Otto session on successful login
            after_login do
              OT.info "[auth] User logged in: #{account[:email]}"

              # Clear rate limiting on successful login
              rate_limit_key = "login_attempts:#{account[:email]}"
              redis = Familia.redis(db: 0)
              redis.del(rate_limit_key)

              # Load Otto customer and sync session
              customer = if account[:external_id]
                Onetime::Customer.load_by_extid(account[:external_id])
              else
                Onetime::Customer.load(account[:email])
              end

              # Sync Rodauth session with Otto's session format inline
              session['authenticated'] = true
              session['authenticated_at'] = Time.now.to_i
              session['advanced_account_id'] = account_id
              session['account_external_id'] = account[:external_id]

              if customer
                session['identity_id'] = customer.custid
                session['email'] = customer.email
                session['locale'] = customer.locale || 'en'
              else
                session['email'] = account[:email]
              end

              # Track metadata
              session['ip_address'] = request.ip
              session['user_agent'] = request.user_agent

              OT.info "[otto-integration] Synced session for #{session['email']}"
            end

            before_logout do
              OT.info "[auth] User logging out: #{session['email'] || 'unknown'}"
            end

            after_logout do
              OT.info "[auth] Logout complete"
            end
          end
        end
      end
    end
  end
end
