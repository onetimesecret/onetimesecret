# apps/web/auth/config/features.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  require_relative 'features/account_management'
  require_relative 'features/audit_logging'
  require_relative 'features/mfa'
  require_relative 'features/passwordless'
  require_relative 'features/security'
  require_relative 'features/webauthn'
end
