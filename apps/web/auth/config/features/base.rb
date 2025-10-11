# apps/web/auth/config/features/base.rb

module Auth
  module Config
    module Features
      module Base
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            db Auth::Config::Database.connection

            # HMAC secret for token security
            hmac_secret_value = ENV['HMAC_SECRET'] || ENV['AUTH_SECRET']

            if hmac_secret_value.nil? || hmac_secret_value.empty?
              if Onetime.production?
                raise 'HMAC_SECRET or AUTH_SECRET environment variable must be set in production'
              else
                OT.info '[rodauth] WARNING: Using default HMAC secret for development - DO NOT use in production'
                hmac_secret_value = 'dev-hmac-secret-change-in-prod'
              end
            end

            hmac_secret hmac_secret_value

            # Note: No prefix needed here - Auth app is already mounted at /auth

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
