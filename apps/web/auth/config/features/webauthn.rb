# apps/web/auth/config/features/webauthn.rb

module Auth::Config::Features
  module WebAuthn
    def self.configure(auth)
      # WebAuthn feature
      # auth.enable :webauthn

      # WebAuthn configuration
      auth.webauthn_rp_id do
        # Use the current request host (supports dev/staging/prod)
        request.host
      end

      auth.webauthn_origin do
        # Full origin for WebAuthn challenge verification
        "#{request.scheme}://#{request.host_with_port}"
      end

      auth.webauthn_rp_name 'OnetimeSecret'

      # Table and column configuration
      # Note: account_webauthn_keys uses composite PK (account_id, webauthn_id)
      auth.webauthn_keys_table :account_webauthn_keys
      # auth.webauthn_keys_account_id_column :account_id
      # auth.webauthn_keys_webauthn_id_column :webauthn_id
      # auth.webauthn_keys_public_key_column :public_key
      auth.webauthn_keys_sign_count_column :sign_count
      auth.webauthn_keys_last_use_column :last_use

      auth.webauthn_user_ids_table :account_webauthn_user_ids
      # auth.webauthn_user_ids_account_id_column :account_id
      # auth.webauthn_user_ids_webauthn_id_column :webauthn_id

      # WebAuthn challenge configuration
      auth.webauthn_setup_timeout 60_000  # 60 seconds for user interaction during setup
      auth.webauthn_auth_timeout 60_000   # 60 seconds for user interaction during auth

      # User verification: preferred (use if available, but don't require)
      # This enables Face ID, Touch ID, Windows Hello
      auth.webauthn_user_verification 'preferred'

      # Authenticator selection: allows both platform and cross-platform
      # (Face ID, Touch ID, Windows Hello AND YubiKey)
      # Setting to nil allows both types
      auth.webauthn_authenticator_selection do
        { authenticatorAttachment: nil }
      end

      # Routes (relative to /auth mount point)
      auth.webauthn_setup_route 'webauthn-setup'
      auth.webauthn_auth_route 'webauthn-auth'
      auth.webauthn_remove_route 'webauthn-remove'

      # JSON API response configuration
      # In JSON mode, flash methods automatically become JSON responses
      auth.webauthn_setup_error_flash 'Error setting up biometric/security key'
      auth.webauthn_auth_error_flash 'Biometric/security key authentication failed'
      auth.webauthn_invalid_remove_param_message 'Invalid security key credential'
      auth.webauthn_invalid_auth_param_message 'Invalid authentication data'
      auth.webauthn_invalid_setup_param_message 'Invalid registration data'

      # NOTE: Passwordless WebAuthn login is enabled by default
      # Users can sign in with ONLY their biometric/security key
      # Autofill can be configured via webauthn_auth_js customization if needed
    end
  end
end
