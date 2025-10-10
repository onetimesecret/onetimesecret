# apps/web/auth/config/features/account_management.rb

module Auth
  module Config
    module Features
      module Base
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            db Auth::Config::Database.connection

            # HMAC secret for token security
            hmac_secret ENV['HMAC_SECRET'] || ENV['AUTH_SECRET'] || 'dev-hmac-secret-change-in-prod'

            prefix '/auth'

            # JSON-only mode
            enable :json
            json_response_success_key :success
            json_response_error_key :error
            only_json? true

            # Use email as the account identifier
            account_id_column :id
            login_column :email
            login_label 'Email'

            # Session configuration (unified with other apps)
            session_key 'onetime.session'
          end
        end
      end
    end
  end
end
