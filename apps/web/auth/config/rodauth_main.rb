# frozen_string_literal: true

require_relative 'database'

module Auth
  module Config
    module RodauthMain
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

          # 5. Configure hooks for account lifecycle
          after_create_account do
            OT.info "[auth] New account created: #{account[:email]} (ID: #{account_id})"

            # Create Otto customer inline
            begin
              # Create or load customer using email as custid
              customer = if Onetime::Customer.exists?(account[:email])
                Onetime::Customer.load(account[:email])
              else
                cust = Onetime::Customer.create! email: account[:email]
                cust.update_passphrase('') # Rodauth manages password
                cust.role = 'customer'
                cust.verified = '1' # Rodauth handles verification
                cust.save
                cust
              end

              OT.info "[otto-integration] Created/loaded customer: #{customer.custid}"

              # Store Otto's derived extid in Rodauth
              db = Auth::Config::Database.connection
              db[:accounts].where(id: account_id).update(external_id: customer.extid)
              OT.info "[otto-integration] Linked Rodauth account #{account_id} to Otto extid: #{customer.extid}"
            rescue => e
              OT.le "[otto-integration] Error creating Otto customer: #{e.message}"
              OT.le e.backtrace.join("
") if Onetime.development?
              # Don't fail account creation
            end
          end

          after_close_account do
            OT.info "[auth] Account closed: #{account[:email]} (ID: #{account_id})"

            # Cleanup Otto customer inline
            begin
              if account[:external_id]
                customer = Onetime::Customer.load_by_extid(account[:external_id])
                if customer
                  customer.destroy!
                  OT.info "[otto-integration] Deleted Otto customer: #{customer.custid} (extid: #{customer.extid})"
                else
                  OT.info "[otto-integration] Otto customer not found for extid: #{account[:external_id]}"
                end
              end
            rescue => e
              OT.le "[otto-integration] Error cleaning up Otto customer: #{e.message}"
              OT.le e.backtrace.join("
") if Onetime.development?
              # Don't fail account closure
            end
          end

          # Only configure verify_account hook if feature is enabled
          if ENV['RACK_ENV'] != 'test'
            after_verify_account do
              OT.info "[auth] Account verified: #{account[:email]}"

              # Update Otto customer verification status if exists
              if account[:external_id]
                customer = Onetime::Customer.load_by_extid(account[:external_id])
                if customer
                  customer.verified = '1'
                  customer.save
                end
              end
            end
          end

          # 6. Configure authentication hooks
          after_login do
            OT.info "[auth] User logged in: #{account[:email]}"

            # Load Otto customer and sync session
            customer = if account[:external_id]
              Onetime::Customer.load_by_extid(account[:external_id])
            else
              Onetime::Customer.load(account[:email])
            end

            # Sync Rodauth session with Otto's session format inline
            session['authenticated'] = true
            session['authenticated_at'] = Time.now.to_i
            session['advanced_account_id'] = account_id
            session['account_external_id'] = account[:external_id]

            if customer
              session['identity_id'] = customer.custid
              session['email'] = customer.email
              session['locale'] = customer.locale || 'en'
            else
              session['email'] = account[:email]
            end

            # Track metadata
            session['ip_address'] = request.ip
            session['user_agent'] = request.user_agent

            OT.info "[otto-integration] Synced session for #{session['email']}"
          end

          before_logout do
            OT.info "[auth] User logging out: #{session['email'] || 'unknown'}"
          end

          after_logout do
            OT.info "[auth] Logout complete"
          end

          # 7. Configure password reset hooks
          after_reset_password_request do
            OT.info "[auth] Password reset requested for: #{account[:email]}"
          end

          after_reset_password do
            OT.info "[auth] Password reset for: #{account[:email]}"
          end

          after_change_password do
            OT.info "[auth] Password changed for: #{account[:email]}"

            # Update Otto customer password hash if needed
            # Note: Rodauth manages passwords, so Otto just tracks metadata
            if account[:external_id]
              customer = Onetime::Customer.load_by_extid(account[:external_id])
              if customer
                customer.passphrase_updated = Time.now.to_i
                customer.save
              end
            end
          end

          # 8. Configure MFA hooks (if MFA features are enabled)
          # These would be added when MFA features are enabled
          # after_otp_setup { ... }
          # after_otp_disable { ... }
        end
      end
    end
  end
end
