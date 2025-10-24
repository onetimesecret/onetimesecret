# apps/web/auth/config/features.rb

module Auth::Config::Features
  require_relative 'features/account_management'
  require_relative 'features/mfa'
  require_relative 'features/passwordless'
  require_relative 'features/security'
  require_relative 'features/webauthn'
end
