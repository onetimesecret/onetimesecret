# apps/web/auth/config.rb

require_relative 'config/database'
require_relative 'config/features'
require_relative 'config/hooks'

module Auth
  module Config
    def self.configure
        proc do
          # 1. Database connection
          db Auth::Config::Database.connection

          # 2. Enable all required features first
          features = [:json, :login, :logout, :create_account, :close_account,
                      :change_password, :reset_password]

          # Only enable verify_account in non-test environments
          features << :verify_account unless ENV['RACK_ENV'] == 'test'

          enable *features

          # 3. Basic configuration
          # HMAC secret for session integrity - critical security parameter
          hmac_secret_value = ENV['HMAC_SECRET'] || ENV['AUTH_SECRET']

          if hmac_secret_value.nil? || hmac_secret_value.empty?
            if Onetime.production?
              raise 'HMAC_SECRET or AUTH_SECRET environment variable must be set in production'
            else
              OT.info '[rodauth] WARNING: Using default HMAC secret for development - DO NOT use in production'
              hmac_secret_value = 'dev-hmac-secret-change-in-prod'
            end
          end

          hmac_secret hmac_secret_value

          # Note: No prefix needed here - Auth app is already mounted at /auth

          # JSON-only mode configuration
          json_response_success_key :success
          json_response_error_key :error
          only_json? true

          # Account configuration
          account_id_column :id
          login_column :email
          login_label 'Email'

          # Session configuration (unified with other apps)
          session_key 'onetime.session'

          # Password requirements
          password_minimum_length 8

          # Email configuration
          email_from 'noreply@onetimesecret.com'
          email_subject_prefix '[OneTimeSecret] '

          # SMTP configuration for email delivery
          send_email do |email|
            if ENV['RACK_ENV'] == 'test'
              # Test environment: log emails instead of sending
              OT.info "[email] Skipping email to #{email[:to]}: #{email[:subject]}"
            elsif ENV['MAILPIT_SMTP_HOST']
              # Use Mailpit for development/CI
              require 'net/smtp'
              smtp_host = ENV['MAILPIT_SMTP_HOST'] || 'localhost'
              smtp_port = (ENV['MAILPIT_SMTP_PORT'] || '1025').to_i

              Net::SMTP.start(smtp_host, smtp_port) do |smtp|
                smtp.send_message(
                  "From: #{email[:from]}
To: #{email[:to]}
Subject: #{email[:subject]}

#{email[:body]}",
                  email[:from],
                  email[:to]
                )
              end
              OT.info "[email] Sent email to #{email[:to]} via Mailpit"
            else
              # Production: use default Rodauth email delivery
              # Will use Net::SMTP with default settings
              OT.info "[email] Sending email to #{email[:to]}: #{email[:subject]}"
            end
          end

          # 4. Override authentication check for Redis session compatibility
          def authenticated?
            super && redis_session_valid?
          end

          def redis_session_valid?
            return false unless session['authenticated_at']
            return false unless session['account_external_id'] || session['advanced_account_id']

            # Check session age against configured expiry
            max_age = Onetime.auth_config.session['expire_after'] || 86400
            age = Time.now.to_i - session['authenticated_at'].to_i
            age < max_age
          end

          # 5. Load and configure all hooks from modular files
          [
            Hooks::Validation.configure,
            Hooks::RateLimiting.configure,
            Hooks::AccountLifecycle.configure,
            Hooks::Authentication.configure,
            Hooks::OttoIntegration.configure
          ].each do |hook_proc|
            instance_eval(&hook_proc)
          end

          # 6. Configure MFA hooks (if MFA features are enabled)
          # These would be added when MFA features are enabled
          # after_otp_setup { ... }
          # after_otp_disable { ... }
        end
      end
    end
  end
