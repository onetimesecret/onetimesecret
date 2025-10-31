# apps/web/auth/config/hooks/webauthn.rb
#
# ==============================================================================
# USER JOURNEY: WEBAUTHN AUTHENTICATION (BIOMETRIC/SECURITY KEY)
# ==============================================================================
#
# This file configures Rodauth hooks for WebAuthn authentication, enabling
# users to log in using biometric authentication (fingerprint, Face ID) or
# physical security keys (YubiKey, Titan Key).
#
# WEBAUTHN OVERVIEW:
# WebAuthn is a W3C standard that allows passwordless authentication using:
# - Biometric sensors (Touch ID, Face ID, Windows Hello)
# - Hardware security keys (YubiKey, Titan Key, FIDO2 devices)
# - Platform authenticators (built into devices)
#
# USER JOURNEY - CREDENTIAL REGISTRATION:
#
# 1. USER INITIATES WEBAUTHN SETUP
#    - User navigates to security settings
#    - Clicks "Add Security Key" or "Add Biometric"
#    - Server generates challenge (random bytes)
#
# 2. BROWSER PROMPTS FOR AUTHENTICATION
#    - Browser shows native prompt: "Use Touch ID?" or "Insert security key"
#    - User provides biometric or inserts/taps security key
#    - Device generates public/private key pair
#    - Private key stays on device (never sent to server)
#    - Public key sent to server with attestation
#
# 3. CREDENTIAL STORED (after_webauthn_setup)
#    - Server validates attestation
#    - Public key stored in account_webauthn_keys table
#    - Credential assigned friendly name (e.g., "MacBook Touch ID")
#    - User sees confirmation: "Security key added successfully"
#
# USER JOURNEY - PASSWORDLESS LOGIN:
#
# 1. USER VISITS LOGIN PAGE
#    - Option: Enter email OR use browser autofill
#    - Passwordless mode: No password field shown
#    - User clicks "Sign in with Security Key" or enters email
#
# 2. WEBAUTHN AUTHENTICATION PROMPT (before_webauthn_auth)
#    - Server generates authentication challenge
#    - Browser shows prompt: "Use Touch ID to sign in?"
#    - User provides biometric or taps security key
#
# 3. CRYPTOGRAPHIC VERIFICATION
#    - Device signs challenge with private key
#    - Signed challenge sent to server
#    - Server verifies signature using stored public key
#    - Success: User authenticated without password
#    - Failure: Error message, user can try again or use password
#
# 4. AUTHENTICATED SESSION
#    - Session established with full authentication
#    - Timestamp updated in account_webauthn_keys.last_use
#    - User redirected to dashboard
#    - Base after_login hook fires (session sync, logging)
#
# SECURITY BENEFITS:
# - Phishing resistant (challenge tied to domain)
# - No password to steal or forget
# - Private key never leaves device
# - Multi-factor by design (possession + biometric/PIN)
# - Resistant to credential stuffing attacks
#
# ==============================================================================

module Auth::Config::Hooks
      module WebAuthn
        def self.configure(auth)

      # CONFIGURATION NOTE:
      # Passwordless WebAuthn login is enabled by default - users can sign in
      # with ONLY their biometric/security key, no password required.
      #
      # Browser autofill integration allows users to select their credential
      # from browser's saved credentials list for one-click authentication.
      # Customize via webauthn_auth_js if autofill behavior needs adjustment.

      # ========================================================================
      # HOOK: After WebAuthn Registration (Credential Stored)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after user successfully registers a WebAuthn credential
      # (biometric or security key). The credential is now stored and ready to use.
      #
      # USER ACTION: Provided biometric or tapped security key during setup
      # SERVER ACTION: Validated attestation and stored public key
      #
      # WHAT HAPPENS:
      # 1. Browser's WebAuthn API collected credential from authenticator
      # 2. Rodauth validated attestation and credential format
      # 3. Public key stored in account_webauthn_keys table with:
      #    - account_id (owner of credential)
      #    - webauthn_id (unique credential identifier)
      #    - public_key (for signature verification)
      #    - sign_count (replay attack prevention)
      #    - last_use (tracking timestamp)
      # 4. **THIS HOOK FIRES** for logging and timestamp update
      #
      # DATABASE STATE:
      # - account_webauthn_keys has new row with credential data
      # - User can now authenticate with this credential
      # - Multiple credentials can be registered per account
      #
      # USER EXPERIENCE:
      # - User sees "Security key added successfully" message
      # - Credential appears in security settings list
      # - Can assign friendly name (e.g., "Work MacBook", "YubiKey")
      # - Can immediately use for login
      #
      auth.after_webauthn_setup do
        Onetime.get_logger('Auth::WebAuthn').info 'WebAuthn credential registered',
          account_id: account[:id],
          email: account[:email],
          webauthn_id: param(webauthn_setup_webauthn_id_param)

        # Update last_use timestamp to track when credential was registered
        # This helps users identify recently added credentials
        db[webauthn_keys_table]
          .where(webauthn_keys_account_id_column => account_id,
                  webauthn_keys_webauthn_id_column => param(webauthn_setup_webauthn_id_param))
          .update(webauthn_keys_last_use_column => Sequel::CURRENT_TIMESTAMP)
      end

      # ========================================================================
      # HOOK: Before WebAuthn Authentication (Login Attempt)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires when user attempts to authenticate using WebAuthn.
      # User has provided biometric or tapped security key to sign challenge.
      #
      # USER ACTION: Provided biometric or tapped security key at login prompt
      # SERVER ACTION: About to verify cryptographic signature
      #
      # WHAT HAPPENS:
      # 1. User clicked "Sign in with Security Key" or browser autofill
      # 2. Server generated cryptographic challenge (random bytes)
      # 3. Browser prompted: "Use Touch ID?" or "Insert security key"
      # 4. User provided biometric or tapped security key
      # 5. Authenticator signed challenge with private key
      # 6. **THIS HOOK FIRES** before signature verification
      # 7. Rodauth verifies signature using stored public key
      # 8. Success: User authenticated, after_login hook fires
      # 9. Failure: after_webauthn_auth_failure hook fires
      #
      # AUTHENTICATION FLOW:
      # - Signature verified against public key in account_webauthn_keys
      # - Sign count validated (must increment, prevents replay attacks)
      # - Challenge must match (prevents man-in-the-middle attacks)
      # - Domain must match (prevents phishing)
      #
      # USER EXPERIENCE:
      # - Success: Instant login, redirected to dashboard
      # - Failure: "Authentication failed" error, can retry
      # - Much faster than password entry
      # - No typing required, works on mobile and desktop
      #
      auth.before_webauthn_auth do
        Onetime.get_logger('Auth::WebAuthn').debug 'Processing WebAuthn authentication',
          account_id: account[:id]

        # NOTE: Session synchronization happens after successful verification
        # The base after_login hook will fire to:
        # - Sync session data (user_id, email, etc.)
        # - Update last_login timestamp
        # - Log successful authentication
        # - Redirect to intended destination
      end

      # ========================================================================
      # HOOK: After WebAuthn Authentication Failure
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires when WebAuthn authentication fails. The signature
      # verification did not succeed, or another validation step failed.
      #
      # USER ACTION: Attempted to authenticate with biometric/security key
      # SERVER ACTION: Signature verification failed
      #
      # COMMON FAILURE SCENARIOS:
      # 1. User cancelled browser prompt (didn't provide biometric)
      # 2. Wrong security key used (not registered for this account)
      # 3. Sign count decreased (potential cloned credential)
      # 4. Challenge expired (took too long to respond)
      # 5. Credential revoked or deleted
      # 6. Browser/device not compatible with WebAuthn
      #
      # WHAT HAPPENS:
      # 1. Rodauth signature verification failed
      # 2. **THIS HOOK FIRES** for logging and monitoring
      # 3. Error message shown to user
      # 4. User remains unauthenticated
      #
      # USER EXPERIENCE:
      # - User sees error message: "Authentication failed"
      # - Can retry with same credential
      # - Can try different credential if multiple registered
      # - Can fall back to password authentication if enabled
      # - Security team may investigate repeated failures
      #
      # SECURITY CONSIDERATIONS:
      # - Multiple failures may indicate attack attempt
      # - Sign count regression indicates credential cloning
      # - Log failure for security monitoring and alerts
      #
      auth.after_webauthn_auth_failure do
        Onetime.get_logger('Auth::WebAuthn').warn 'WebAuthn authentication failed',
          account_id: account[:id],
          email: account[:email]

        # Failure logged for security monitoring
        # Consider rate limiting or account alerts after repeated failures
      end

      # ========================================================================
      # HOOK: Before WebAuthn Credential Removal
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires when user removes a WebAuthn credential from their
      # security settings. The credential will be deleted after this hook.
      #
      # USER ACTION: Clicked "Remove" button next to credential in settings
      # SERVER ACTION: About to delete credential from database
      #
      # WHAT HAPPENS:
      # 1. User navigates to security settings
      # 2. Views list of registered WebAuthn credentials
      #    - Each shows: name, type (biometric/security key), last used
      # 3. Clicks "Remove" on specific credential
      # 4. Confirms removal (if confirmation enabled)
      # 5. **THIS HOOK FIRES** for logging before deletion
      # 6. Credential deleted from account_webauthn_keys table
      # 7. User sees "Credential removed successfully"
      #
      # DATABASE STATE:
      # - Credential still exists but about to be deleted
      # - After hook completes, row removed from account_webauthn_keys
      # - User cannot authenticate with this credential anymore
      #
      # USER EXPERIENCE:
      # - Credential disappears from settings list
      # - If last credential: Warning about losing passwordless access
      # - May need to use password or add new credential
      # - Cannot undo removal (must re-register if needed)
      #
      # COMMON SCENARIOS:
      # - Lost device (remove compromised credential)
      # - Upgraded device (remove old, add new)
      # - Security cleanup (remove unused credentials)
      # - Switching authentication methods
      #
      # SECURITY CONSIDERATIONS:
      # - Log removal for audit trail
      # - Consider notification email if credential removed
      # - Prevent account lockout if removing last auth method
      #
      auth.before_webauthn_remove do
        Onetime.get_logger('Auth::WebAuthn').info 'Removing WebAuthn credential',
          account_id: account[:id],
          email: account[:email],
          webauthn_id: param(webauthn_remove_webauthn_id_param)

        # Log credential removal for security audit
        # Consider sending notification email to account owner
        # System may prevent removal if it's the only auth method
      end

    end
  end
end
