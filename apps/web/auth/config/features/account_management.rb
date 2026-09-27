# apps/web/auth/config/features/account_management.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  module AccountManagement
    def self.configure(auth)
      # Account lifecycle features
      auth.enable :create_account
      auth.enable :close_account
      auth.enable :change_password
      auth.enable :reset_password

      configure_create_account_response(auth)

      # Only configure verify_account if the feature is enabled
      # (disabled in test mode via YAML config: RACK_ENV != 'test')
      if Onetime.auth_config.verify_account_enabled?
        auth.enable :verify_account

        # Password is set during account creation, not during verification
        # This prevents verify_account from requiring password fields
        auth.verify_account_set_password? false

        # Redirect after email verification.
        #
        # Precedence (issue #4305): a valid paid-plan intent (#3126) wins, then
        # the `?redirect=` the user started signup with, then /account.
        #
        # DOES NOT APPLY TO JSON/SPA CLIENTS. Rodauth's json feature overrides
        # `redirect(_)` to discard its argument and return the JSON body
        # instead (rodauth-2.45.0 features/json.rb:205-208), and
        # verify_account_response calls `redirect verify_account_redirect`
        # (rodauth.rb:254) — so this block still RUNS (Ruby evaluates the
        # argument, which is why the session keys are consumed either way) but
        # its return value is thrown away. The SPA gets its destination from
        # json_response[:redirect], set in the after_verify_account hook. Kept
        # here for the non-JSON form-post path, which is a real 302.
        auth.verify_account_redirect do
          # Consume BOTH keys before picking: chaining the deletes with `||`
          # short-circuits, leaving the losing key in the session to resurface
          # on a later verification in the same session. Single-use means
          # single-use for both.
          checkout_path = session.delete('plan_checkout_redirect')
          auth_path     = session.delete('auth_redirect')

          checkout_path || auth_path || '/account'
        end

        # Suppress verification email only for valid invite signups.
        # The invite link proves email ownership, so no extra verification needed.
        #
        # As of issue #3221's fix, the invitation token is no longer consumed
        # by the after_create_account hook — acceptance happens via the explicit
        # POST /api/invite/:token/accept call the frontend issues against the
        # established session. find_by_token therefore continues to resolve the
        # invitation across the entire signup lifecycle (before/during/after
        # account creation).
        #
        # SECURITY: Token must be validated here — checking the raw param alone
        # would let an attacker add invite_token=garbage to suppress the email
        # for any signup, enabling email squatting.
        auth.send_verify_account_email do
          # Use Rodauth's `param` rather than `request.params['invite_token']` so
          # this works under internal_request too (internal_request only populates
          # rodauth.params, not the Rack request body).
          invite_token = param_or_nil('invite_token').to_s.strip
          if invite_token.empty?
            super()
          else
            invitation   = Onetime::OrganizationMembership.find_by_token(invite_token)
            valid_invite = invitation &&
                           invitation.pending? &&
                           !invitation.expired? &&
                           OT::Utils.normalize_email(invitation.invited_email) ==
                           OT::Utils.normalize_email(param(login_param))

            if valid_invite
              Auth::Logging.log_auth_event(
                :verify_email_suppressed,
                level: :info,
                email: OT::Utils.obscure_email(param(login_param)),
                reason: 'valid_invite_token',
                invite_token_prefix: invite_token[0..7],
                organization_id: invitation.organization_objid,
              )
            else
              reason = if invitation.nil? then 'token_not_found'
                       elsif !invitation.pending? then 'not_pending'
                       elsif invitation.expired? then 'expired'
                       else 'email_mismatch'
                       end
              Auth::Logging.log_auth_event(
                :verify_email_sent_despite_token,
                level: :warn,
                email: OT::Utils.obscure_email(param(login_param)),
                reason: reason,
                invite_token_prefix: invite_token[0..7].gsub(/[^a-zA-Z0-9\-_]/, '?'),
              )
              super()
            end
          end
        end
      end

      # Auto-login after invite signup (flag set in after_create_account hook)
      auth.create_account_autologin? do
        should_autologin = @invite_accepted == true
        Auth::Logging.log_auth_event(
          :create_account_autologin_decision,
          level: :debug,
          email: OT::Utils.obscure_email(param(login_param)),
          autologin: should_autologin,
          invite_accepted: @invite_accepted == true,
        )
        should_autologin
      end

      # Have successful login redirect back to originally requested page
      # @see login_return.rdoc
      auth.login_return_to_requested_location? true

      # Password requirements
      auth.password_minimum_length 8

      # Disable password confirmation field requirement
      # UI sends single password field, not password + confirmation
      auth.require_password_confirmation? false

      # Disable login confirmation field requirement, for the same reason: the
      # SPA signup form sends a single email field, never `login-confirm`.
      # Rodauth defaults this to true (login_password_requirements_base.rb) and
      # only verify_account overrides it to false, so with verify_account
      # disabled (AUTH_VERIFY_ACCOUNT_ENABLED=false) every SPA signup answered
      # 422 "logins do not match". Stated here so signup does not depend on
      # which features are enabled. change_login, the only other route that
      # reads it, is not enabled.
      #
      # Not an access control: the field is a typo guard the caller fills in
      # itself, so any client could always pass it by echoing the login. Who
      # may create which account is unchanged.
      auth.require_login_confirmation? false

      # SECURITY: Genericize the "same as current password" error.
      #
      # reset_password / change_password run an unconditional
      # `password_match?(new_password)` check (rodauth reset_password.rb:134,
      # change_password.rb:48) and, on a match, emit
      # `same_as_existing_password_message`. Rodauth's default text
      # ("invalid password, same as current password") is returned verbatim
      # in the JSON `field-error` tuple and rendered to the user.
      #
      # On the *reset* flow this is an information-disclosure oracle: a holder
      # of a valid reset token can submit a suspected password and have the
      # response confirm it matches the account's current password — without
      # changing it — enabling stealthy credential-reuse checks (OWASP
      # Authentication Cheat Sheet: use generic messages). A generic string
      # removes the explicit confirmation. The check itself is not iterable
      # (a non-matching submission completes the reset), so this is the
      # proportionate remediation; suppressing the check entirely would
      # require overriding Rodauth's reset internals.
      auth.same_as_existing_password_message 'invalid password'

      # Custom error messages
      # Override Rodauth's default generic error message
      # In JSON mode, this becomes the "error" field in the response
      # Field-specific errors are still returned in "field-error" array
      auth.create_account_error_flash 'Unable to create account'
    end

    # JSON clients cannot infer whether account creation requires an email
    # round-trip. Name the usable next step in the success response; any
    # billing_redirect already added by after_create_account remains the
    # validated checkout intent to follow after sign-in.
    #
    # The answer is the status of the account this request just created. A
    # login that already has an account never gets this far: every duplicate
    # gets the generic 400 before or at the INSERT
    # (overrides/duplicate_signup.rb). The only input that changes the answer
    # is an invite token the caller sent, and before_create_account already
    # refuses a token that is not pending for that login with the same
    # generic error (hooks/account.rb). So the answer reveals nothing about
    # any existing account.
    #
    # With verify_account loaded, a new account starts unverified and needs
    # the emailed link. That includes webauthn_verify_account, which loads
    # verify_account even when verify_account_enabled? is false. An invite
    # signup is the exception: after_create_account opens the account and no
    # email is sent, so it answers sign_in.
    #
    # There is no "signed in" answer, although create_account_autologin? logs
    # the invite signup in. That autologin is Rodauth's alone: it does not run
    # after_login, so SyncSession never sets the app's `authenticated` flag,
    # and /bootstrap/me and every app route treat the caller as anonymous.
    # Signing in is still the next step that works. The SPA's own invite form
    # posts to /api/invite/:token/signup, which sets that flag itself.
    #
    # The success text follows the same account status. verify_account
    # replaces create_account's notice with "An email has been sent to you
    # with a link to verify your account" for every signup (rodauth 2.45.0
    # verify_account.rb, create_account_notice_flash). An account opened at
    # signup got no email, so it gets create_account's own "Your account has
    # been created", the text a signup already gets without verify_account.
    #
    # Kept apart from configure so a spec can apply it to a Rodauth app with
    # verify_account loaded, which RACK_ENV=test turns off
    # (apps/web/auth/spec/config/features/account_management_spec.rb).
    def self.configure_create_account_response(auth)
      auth.create_account_notice_flash do
        open_account? ? 'Your account has been created' : super()
      end

      auth.create_account_response do
        json_response[:next_action] = open_account? ? 'sign_in' : 'verify_email' if json_request?
        super()
      end
    end
  end
end
