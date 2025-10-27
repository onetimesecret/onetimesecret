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
    auth.json_response_custom_error_status? true
    auth.only_json? true

    # Use email as the account identifier
    # auth.account_id_column :id
    auth.login_column :email
    auth.login_label 'Email'

    # Configure which columns to load from accounts table
    # IMPORTANT: Include external_id for Redis-SQL synchronization
    auth.account_select [:id, :email, :status_id, :external_id]

    # Session configuration (unified with other apps)
    # The session_key config is for the session cookie name
    auth.session_key 'onetime.session'
  end

  private_class_method

  # How it works for MFA
  #
  # During Setup:
  # 1. Generate raw secret: ABCD1234 (example)
  # 2. Generate HMAC secret: HMAC(ABCD1234, hmac_secret_key) = WXYZ5678
  # 3. QR code contains: WXYZ5678 (HMAC version)
  # 4. Manual entry shows: WXYZ5678 (HMAC version)
  # 5. User scans/enters WXYZ5678 into authenticator app
  # 6. Authenticator generates codes from WXYZ5678
  # 7. User enters code → Server validates against WXYZ5678 (from session)
  # 8. Database stores: ABCD1234 (raw version)
  #
  # During Login (future authentications):
  # 1. Database contains: ABCD1234 (raw secret)
  # 2. Server reads ABCD1234 from database
  # 3. Server computes: HMAC(ABCD1234, hmac_secret_key) = WXYZ5678
  # 4. User's authenticator has: WXYZ5678 (from setup)
  # 5. User enters code → Server validates against WXYZ5678
  #
  # Security Benefit:
  # - If database is compromised, attacker gets: ABCD1234 (raw)
  # - But to generate valid OTP codes, you need: WXYZ5678 (HMAC)
  # - Which requires knowing the hmac_secret configuration value (stored
  #   in ENV on the application server)

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
