# apps/web/auth/config/features/passwordless.rb

module Auth
  module Config
    module Features
      module Passwordless
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Email Auth (Magic Links)
            enable :email_auth

            # Email auth configuration
            email_auth_deadline_interval 86400  # 24 hours
            email_auth_skip_resend_email_within 300  # 5 minutes

            # Table and column configuration
            email_auth_table :account_email_auth_keys
            email_auth_id_column :account_id
            email_auth_key_column :key
            email_auth_deadline_column :deadline
            email_auth_email_last_sent_column :email_last_sent

            # Email content for magic links
            email_auth_email_subject 'Login Link'
            email_auth_email_body do
              <<~EMAIL
                Hello,

                You requested a login link for your OneTimeSecret account.

                Click the link below to sign in:

                #{email_auth_email_link}

                This link will expire in 24 hours.

                If you didn't request this, you can safely ignore this email.

                Best regards,
                The OneTimeSecret Team
              EMAIL
            end

            # JSON API response configuration
            email_auth_request_error_flash 'Error requesting login link'
            email_auth_email_sent_notice 'Login link sent to your email'
            email_auth_email_recently_sent_error_flash 'Login link was recently sent, please check your email'
            email_auth_deadline_passed_error_flash 'Login link has expired'

            # Routes (relative to /auth mount point)
            email_auth_route 'email-login'
            email_auth_request_route 'email-login-request'

            # Session key for storing token during auth flow
            email_auth_session_key 'email_auth_key'

            # Hook: After successful email auth login
            after_email_auth do
              # Track login in audit log
              SemanticLogger['Auth::EmailAuth'].info 'Magic link login successful',
                account_id: account[:id],
                email: account[:email]

              # Sync with Redis session if needed
              session['authenticated_at'] = Familia.now
              session['account_external_id'] = account[:external_id]
              session['authentication_method'] = 'email_auth'
            end

            # Hook: Before sending magic link email
            before_email_auth_email_send do
              SemanticLogger['Auth::EmailAuth'].info 'Sending magic link',
                account_id: account[:id],
                email: account[:email]
            end
          end
        end
      end
    end
  end
end
