# apps/web/auth/config/features/webauthn_config.rb

module Auth
  module Config
    module Features
      module WebAuthnConfig
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # WebAuthn feature
            enable :webauthn

            # WebAuthn configuration
            webauthn_rp_id do
              # Use the current request host (supports dev/staging/prod)
              request.host
            end

            webauthn_origin do
              # Full origin for WebAuthn challenge verification
              "#{request.scheme}://#{request.host_with_port}"
            end

            webauthn_rp_name 'OneTimeSecret'

            # Table and column configuration
            # Note: account_webauthn_keys uses composite PK (account_id, webauthn_id)
            webauthn_keys_table :account_webauthn_keys
            webauthn_keys_account_id_column :account_id
            webauthn_keys_webauthn_id_column :webauthn_id
            webauthn_keys_public_key_column :public_key
            webauthn_keys_sign_count_column :sign_count
            webauthn_keys_last_use_column :last_use

            webauthn_user_ids_table :account_webauthn_user_ids
            webauthn_user_ids_account_id_column :account_id
            webauthn_user_ids_webauthn_id_column :webauthn_id

            # WebAuthn challenge configuration
            webauthn_timeout 60_000  # 60 seconds for user interaction

            # User verification: preferred (use if available, but don't require)
            # This enables Face ID, Touch ID, Windows Hello
            webauthn_user_verification 'preferred'

            # Authenticator attachment: cross-platform allows both built-in and external
            # (Face ID AND YubiKey)
            webauthn_authenticator_selection_authenticator_attachment nil

            # Routes (relative to /auth mount point)
            webauthn_setup_route 'webauthn-setup'
            webauthn_auth_route 'webauthn-auth'
            webauthn_remove_route 'webauthn-remove'

            # JSON API response configuration
            webauthn_setup_error_flash 'Error setting up biometric/security key'
            webauthn_auth_error_flash 'Biometric/security key authentication failed'
            webauthn_invalid_webauthn_id_message 'Invalid security key credential'

            # Allow passwordless WebAuthn login
            # Users can sign in with ONLY their biometric/security key
            webauthn_autofill? true

            # Hook: After successful WebAuthn registration
            after_webauthn_setup do
              SemanticLogger['Auth::WebAuthn'].info 'WebAuthn credential registered',
                account_id: account[:id],
                email: account[:email],
                webauthn_id: param(webauthn_setup_webauthn_id_param)

              # Update last_use timestamp
              db[webauthn_keys_table]
                .where(webauthn_keys_account_id_column => account_id,
                       webauthn_keys_webauthn_id_column => param(webauthn_setup_webauthn_id_param))
                .update(webauthn_keys_last_use_column => Sequel::CURRENT_TIMESTAMP)
            end

            # Hook: After successful WebAuthn authentication
            after_webauthn_auth do
              SemanticLogger['Auth::WebAuthn'].info 'WebAuthn login successful',
                account_id: account[:id],
                email: account[:email]

              # Sync with Redis session
              session['authenticated_at'] = Familia.now
              session['account_external_id'] = account[:external_id]
              session['authentication_method'] = 'webauthn'

              # Update last_use timestamp for the credential
              db[webauthn_keys_table]
                .where(webauthn_keys_account_id_column => account_id,
                       webauthn_keys_webauthn_id_column => param(webauthn_auth_webauthn_id_param))
                .update(webauthn_keys_last_use_column => Sequel::CURRENT_TIMESTAMP)
            end

            # Hook: Before WebAuthn credential removal
            before_webauthn_remove do
              SemanticLogger['Auth::WebAuthn'].info 'Removing WebAuthn credential',
                account_id: account[:id],
                email: account[:email],
                webauthn_id: param(webauthn_remove_webauthn_id_param)
            end

            # Custom: Get WebAuthn credentials list for account
            # Used by frontend to show registered devices
            auth_class_eval do
              def webauthn_credentials_for_account
                db[webauthn_keys_table]
                  .where(webauthn_keys_account_id_column => account_id)
                  .select(
                    Sequel.as(webauthn_keys_webauthn_id_column, :id),
                    webauthn_keys_last_use_column,
                    webauthn_keys_sign_count_column
                  )
                  .all
              end
            end
          end
        end
      end
    end
  end
end
