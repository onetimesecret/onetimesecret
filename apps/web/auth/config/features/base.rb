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

            # Table column configurations
            # All Rodauth tables use account_id as FK, not id
            password_hash_table :account_password_hashes
            password_hash_id_column :account_id

            # Configure which columns to load from accounts table
            # IMPORTANT: Include external_id for Redis-SQL synchronization
            account_select [:id, :email, :status_id, :external_id]

            # Session configuration (unified with other apps)
            # The session_key config is for the session cookie name
            session_key 'account_id'

            # Override session methods to use the Core app's session structure
            # # Core app stores account ID in session[:account_id]
            # session_value do
            #   session[:account_id]
            # end

            # set_session_value do |id|
            #   session[:account_id] = id
            # end

            # clear_session do
            #   session.delete(:account_id)
            #   super()
            # end
          end
        end
      end
    end
  end
end
