# apps/web/auth/config/features.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  require_relative 'features/account_management'
  require_relative 'features/active_sessions'
  require_relative 'features/argon2'
  require_relative 'features/audit_logging'
  require_relative 'features/email_auth'
  require_relative 'features/hardening'
  require_relative 'features/mfa'
  require_relative 'features/remember_me'
  require_relative 'features/webauthn'
end
