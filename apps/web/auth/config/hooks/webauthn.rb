# apps/web/auth/config/hooks/webauthn.rb

module Auth::Config::Hooks
      module WebAuthn
        def self.configure(auth)

      # Note: Passwordless WebAuthn login is enabled by default
      # Users can sign in with ONLY their biometric/security key
      # Autofill can be configured via webauthn_auth_js customization if needed

      # Hook: After successful WebAuthn registration
      auth.after_webauthn_setup do
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

      # Hook: Before WebAuthn authentication
      auth.before_webauthn_auth do
        SemanticLogger['Auth::WebAuthn'].debug 'Processing WebAuthn authentication',
          account_id: account[:id]

        # Note: Successful login is tracked via session middleware
        # Set session values in base after_login hook
      end

      # Hook: After failed WebAuthn authentication
      auth.after_webauthn_auth_failure do
        SemanticLogger['Auth::WebAuthn'].warn 'WebAuthn authentication failed',
          account_id: account[:id],
          email: account[:email]
      end

      # Hook: Before WebAuthn credential removal
      auth.before_webauthn_remove do
        SemanticLogger['Auth::WebAuthn'].info 'Removing WebAuthn credential',
          account_id: account[:id],
          email: account[:email],
          webauthn_id: param(webauthn_remove_webauthn_id_param)
      end

    end
  end
end
