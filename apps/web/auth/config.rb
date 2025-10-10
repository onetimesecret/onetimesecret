# apps/web/auth/config.rb

require_relative 'config/database'
require_relative 'config/features'
require_relative 'config/hooks'

module Auth
  module Config
    def self.configure
        proc do
          # 1. Load base configuration (database, session, JSON mode)
          Features::Base.configure(self)

          # 2. Load feature configurations
          Features::Authentication.configure(self)
          Features::AccountManagement.configure(self)

          # Optional features (conditionally enabled)
          Features::Security.configure(self) if ENV['ENABLE_SECURITY_FEATURES'] != 'false'
          Features::MFA.configure(self) if ENV['ENABLE_MFA'] == 'true'

          # 3. Email configuration
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

          # 4. Load and configure all hooks from modular files
          [
            Hooks::Validation.configure,
            Hooks::RateLimiting.configure,
            Hooks::AccountLifecycle.configure,
            Hooks::Authentication.configure,
            Hooks::OttoIntegration.configure
          ].each do |hook_proc|
            instance_eval(&hook_proc)
          end
        end
      end
    end
  end
