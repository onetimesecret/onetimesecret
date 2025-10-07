# frozen_string_literal: true

module Auth
  module Config
    module Features
      module Authentication
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Features
            enable :login, :logout

            # Redis session compatibility overrides
            def authenticated?
              super && redis_session_valid?
            end

            def redis_session_valid?
              return false unless session['authenticated_at']
              return false unless session['account_external_id'] || session['advanced_account_id']

              # Check session age against configured expiry
              max_age = Onetime.auth_config.session['expire_after'] || 86400
              age = Familia.now - session['authenticated_at'].to_i
              age < max_age
            end
          end
        end
      end
    end
  end
end
