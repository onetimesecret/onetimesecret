# apps/web/auth/config/features/passwordless.rb

module Auth
  module Config
    module Features
      # Passwordless (Email Magic Links) feature configuration
      #
      module Passwordless
        using Familia::Refinements::TimeLiterals

        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Email Auth (Magic Links)
            enable :email_auth

            # Table and column configuration
            # All Rodauth tables use account_id as FK, not id
            email_auth_table :account_email_auth_keys
            email_auth_id_column :account_id
            email_auth_key_column :key
            email_auth_deadline_column :deadline
            email_auth_email_last_sent_column :email_last_sent

            # Magic links are only valid for a short period so we also keep
            # the resend interval short to avoid user frustration.
            email_auth_deadline_interval 15.minutes
            email_auth_skip_resend_email_within 30.seconds

            # Email content for magic links
            email_auth_email_subject 'Login Link'
            email_auth_email_body do
              <<~EMAIL
                Hello,

                You requested a login link for your OneTimeSecret account.

                Click the link below to sign in:

                #{email_auth_email_link}

                This link will expire in 15 minutes.

                If you didn't request this, you can safely ignore this email.

                Best regards,
                The OneTimeSecret Team
              EMAIL
            end

            # JSON API response configuration
            # In JSON mode, flash methods automatically become JSON responses
            email_auth_request_error_flash 'Error requesting login link'
            email_auth_email_sent_notice_flash 'Login link sent to your email'
            email_auth_email_recently_sent_error_flash 'Login link was recently sent, please check your email'
            email_auth_error_flash 'Login link has expired or is invalid'

            # Routes (relative to /auth mount point)
            email_auth_route 'email-login'
            email_auth_request_route 'email-login-request'

            # Session key for storing token during auth flow
            email_auth_session_key 'email_auth_key'

            # Hook: Before handling email auth route (form submission)
            before_email_auth_route do
              SemanticLogger['Auth'].debug 'Processing magic link authentication'
              # No arguments are passed to the block.
              # You can access request parameters using Rodauth methods like 'param'.
              auth_token = param('key')

              if auth_token.nil? || auth_token.empty?
                msg = 'The email authentication token is missing.'
                SemanticLogger['Auth'].error msg
                set_error_flash msg
                redirect login_path
              end
            end

            # Hook: After sending magic link email
            after_email_auth_request do
              SemanticLogger['Auth'].info 'Magic link email sent',
                account_id: account[:id],
                email: account[:email]

              # NOTE: Successful login is tracked via session middleware
              # Set session values in base after_login hook
            end
          end
        end
      end
    end
  end
end
