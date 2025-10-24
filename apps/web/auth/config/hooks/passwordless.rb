# apps/web/auth/config/hooks/passwordless.rb
#
# ==============================================================================
# USER JOURNEY: PASSWORDLESS EMAIL AUTHENTICATION (MAGIC LINK)
# ==============================================================================
#
# This file configures Rodauth hooks for passwordless authentication via email
# link (also known as "Magic Link" authentication). Users can log in without
# entering a password by clicking a unique link sent to their email.
#
# USER FLOW:
#
# 1. USER REQUESTS MAGIC LINK
#    - User visits login page and enters email address
#    - Clicks "Send Magic Link" button
#    - System generates unique token and stores in database
#    - Email sent with link: https://app.com/email-auth?key=TOKEN
#    - after_email_auth_request hook fires
#
# 2. USER RECEIVES EMAIL
#    - User opens email client
#    - Sees "Log in to OneTime" email with prominent button/link
#    - Link contains time-limited authentication token (typically 15-30 min)
#
# 3. USER CLICKS MAGIC LINK
#    - Browser opens: GET /email-auth?key=TOKEN
#    - before_email_auth_route hook fires to validate token presence
#    - Rodauth validates token exists and hasn't expired
#    - If valid: User automatically logged in
#    - If invalid/expired: Error message, user can request new link
#
# 4. AUTHENTICATED SESSION
#    - Session established with full authentication
#    - Token consumed (one-time use only)
#    - User redirected to dashboard or intended destination
#    - Standard after_login hooks fire (session sync, logging)
#
# SECURITY CONSIDERATIONS:
# - Tokens are single-use and time-limited
# - Token validates email ownership (email is verified through access)
# - No password needed, reduces phishing risk
# - HTTPS required to prevent token interception
# - Token invalidated after use or expiration
#
# ==============================================================================

module Auth::Config::Hooks
  module Passwordless
    def self.configure(auth)
      # ========================================================================
      # HOOK: Before Email Auth Route (Token Validation)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires when the user clicks the magic link in their email
      # and their browser makes a GET request to /email-auth?key=TOKEN
      #
      # USER ACTION: Clicks link in email
      # REQUEST: GET /email-auth?key=abc123def456...
      #
      # WHAT HAPPENS:
      # 1. Extract 'key' parameter from URL query string
      # 2. Validate token is present (not nil or empty)
      # 3. If missing: Redirect to login with error message
      # 4. If present: Continue to Rodauth's token verification
      #    - Rodauth checks token exists in account_email_auth_keys table
      #    - Validates token hasn't expired (default: 1 day)
      #    - Validates token hasn't been used
      # 5. Success: User logged in, token marked as consumed
      # 6. Failure: Error page, user can request new magic link
      #
      # USER EXPERIENCE:
      # - Success: Instant login, redirected to dashboard
      # - Token missing: "Authentication token is missing" error
      # - Token expired: "This link has expired" error
      # - Token used: "This link has already been used" error
      #
      auth.before_email_auth_route do
        SemanticLogger['Auth'].debug 'Processing magic link authentication'

        # Extract authentication token from URL query parameter
        # Expected format: ?key=TOKEN
        auth_token = param('key')

        # Validate token presence before continuing to Rodauth verification
        if auth_token.nil? || auth_token.empty?
          msg = 'The email authentication token is missing.'
          SemanticLogger['Auth'].error msg
          set_error_flash msg
          redirect login_path  # Send user back to login page
        end

        # Token present - Rodauth will now verify validity and expiration
      end

      # ========================================================================
      # HOOK: After Email Auth Request (Magic Link Sent)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after Rodauth successfully generates a magic link token
      # and sends the email to the user. The user has not yet clicked the link.
      #
      # USER ACTION: Submitted email address and clicked "Send Magic Link"
      # SERVER ACTION: Generated token, stored in database, sent email
      #
      # WHAT HAPPENS:
      # 1. Rodauth generates cryptographically secure random token
      # 2. Token stored in account_email_auth_keys table with:
      #    - account_id (links token to user)
      #    - key (the token value)
      #    - deadline (expiration timestamp)
      #    - email_last_sent (rate limiting)
      # 3. Email composed with link: https://app.com/email-auth?key=TOKEN
      # 4. Email sent via configured mailer
      # 5. **THIS HOOK FIRES** for logging and tracking
      #
      # DATABASE STATE:
      # - account_email_auth_keys has new row with unused token
      # - Token valid until deadline (typically 24 hours)
      #
      # USER EXPERIENCE:
      # - User sees "Check your email" confirmation message
      # - Email arrives with "Log in to OneTime" subject
      # - User can click link anytime before expiration
      # - User can request new link if needed (rate limited)
      #
      # NEXT STEPS:
      # - User opens email → clicks link → before_email_auth_route fires
      # - Token validates → user logged in → base after_login hook fires
      #
      auth.after_email_auth_request do
        SemanticLogger['Auth'].info 'Magic link email sent',
          account_id: account[:id],
          email: account[:email]

        # NOTE: Successful login tracking happens later in the flow
        # When user clicks link and authenticates, the base after_login
        # hook will fire to sync session and log successful authentication
      end
    end
  end
end
