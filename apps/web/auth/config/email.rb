# apps/web/auth/config/email.rb
#
# frozen_string_literal: true

require 'onetime/mail'

# Load email submodules
require_relative 'email/helpers'
require_relative 'email/verify_account'
require_relative 'email/reset_password'
require_relative 'email/email_auth'
require_relative 'email/delivery'

module Auth::Config::Email
  def self.configure(auth)
    # Configure Rodauth email settings (shared across all email operations)
    auth.email_from Onetime::Mail::Mailer.from_address
    auth.email_subject_prefix ''  # Templates handle their own prefixes

    # Load sub-configurations in dependency order:
    # 1. Helpers must be first: defines methods used by template blocks
    Helpers.configure(auth)

    # 2. Email templates (use helper methods)
    # Only configure verify_account email if the feature is enabled
    # (verify_account is disabled in test mode - see features/account_management.rb)
    auth_class = auth.instance_variable_get(:@auth)
    if auth_class&.features&.include?(:verify_account)
      VerifyAccount.configure(auth)
    end
    ResetPassword.configure(auth)

    # Only configure email_auth email if the feature is enabled
    # (email_auth is opt-in via ENABLE_EMAIL_AUTH env var)
    if Onetime.auth_config.email_auth_enabled?
      EmailAuth.configure(auth)
    end

    # 3. Delivery mechanism (intercepts all email sending)
    Delivery.configure(auth)

    OT.info '[email] Email templates and delivery configured'
  end
end
