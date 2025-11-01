# apps/web/auth/config/base.rb

require_relative '../database'

module Auth::Config::Base
  def self.configure(auth)
    auth.db Auth::Database.connection

    auth.table_guard_mode :error
    auth.table_guard_sequel_mode :skip
    auth.table_guard_logger Onetime.get_logger('Auth')

    # Configure which columns to load from accounts table
    # IMPORTANT: Include external_id for Redis-SQL synchronization
    # auth.external_identity_column :external_id
    # auth.external_identity_check_columns :autocreate

    # JSON-only mode configuration
    auth.json_response_success_key :success
    auth.json_response_error_key :error
    auth.json_response_field_error_key :'field-error'
    auth.json_response_custom_error_status? true
    auth.only_json? true

    # Use email as the account identifier
    # auth.account_id_column :id
    auth.login_column :email
    auth.login_label 'Email'

    # Session configuration
    # NOTE: session_key is the hash key where account_id is stored in session[]
    # Default is 'account_id', which is what we want to use
    # The session cookie name is configured in the session middleware, not here
    auth.session_key 'account_id'  # Using Rodauth default

    # Override clear_session to properly destroy session and trigger cookie deletion
    # Rodauth's default clear_session only calls session.clear which doesn't delete
    # the session from the store or generate a new session ID. We need session.destroy
    # to trigger delete_session on our custom Onetime::Session store.
    auth.clear_session do
      session.destroy
    end


    # auth.max_invalid_logins 2
    # auth.account_password_hash_column :ph
    # auth.title_instance_variable :@page_title
  end
end
