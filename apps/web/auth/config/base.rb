# apps/web/auth/config/base.rb

require_relative '../database'

module Auth::Config::Base
  def self.configure(auth)
    auth.db Auth::Database.connection

    auth.hmac_secret hmac_secret_value

    # JSON-only mode configuration
    auth.json_response_success_key :success
    auth.json_response_error_key :error
    auth.json_response_field_error_key :'field-error'
    auth.only_json? true

    # Use email as the account identifier
    auth.account_id_column :id
    auth.login_column :email
    auth.login_label 'Email'

    # Configure which columns to load from accounts table
    # IMPORTANT: Include external_id for Redis-SQL synchronization
    auth.account_select [:id, :email, :status_id, :external_id]

    # Table column configurations
    # All Rodauth tables use account_id as FK, not id
    auth.password_hash_table :account_password_hashes
    auth.password_hash_id_column :account_id

    # Session configuration (unified with other apps)
    # The session_key config is for the session cookie name
    auth.session_key 'onetime.session'
  end

  private_class_method

  def self.hmac_secret_value
    # HMAC secret for token security
    hmac_secret_value = ENV['HMAC_SECRET'] || ENV['AUTH_SECRET']

    if hmac_secret_value.nil? || hmac_secret_value.empty?
      if Onetime.production?
        raise 'HMAC_SECRET or AUTH_SECRET environment variable must be set in production'
      else
        OT.info '[rodauth] WARNING: Using default HMAC secret for development only'
        hmac_secret_value = 'dev-hmac-secret-change-in-prod'
      end
    end

    hmac_secret_value
  end
end
