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

      # Only configure verify_account if the feature is enabled
      # (disabled in test mode via YAML config: RACK_ENV != 'test')
      if Onetime.auth_config.verify_account_enabled?
        auth.enable :verify_account

        # Password is set during account creation, not during verification
        # This prevents verify_account from requiring password fields
        auth.verify_account_set_password? false

        # Suppress verification email only for valid invite signups.
        # The invite link proves email ownership, so no extra verification needed.
        #
        # HOOK ORDERING: verify_account's after_create_account calls
        # setup_account_verification (which calls send_verify_account_email)
        # BEFORE the user's after_create_account block runs. This means the
        # token has NOT yet been consumed by AcceptInvitation when this code
        # executes, so find_by_token correctly finds it.
        #
        # SECURITY: Token must be validated here — checking the raw param alone
        # would let an attacker add invite_token=garbage to suppress the email
        # for any signup, enabling email squatting.
        auth.send_verify_account_email do
          invite_token = request.params['invite_token'].to_s.strip
          if invite_token.empty?
            super()
          else
            invitation = Onetime::OrganizationMembership.find_by_token(invite_token)
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

      # Custom error messages
      # Override Rodauth's default generic error message
      # In JSON mode, this becomes the "error" field in the response
      # Field-specific errors are still returned in "field-error" array
      auth.create_account_error_flash 'Unable to create account'
    end
  end
end
