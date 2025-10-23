# apps/web/auth/config/features.rb

module Auth
  module Config
    module Features
      require_relative 'features/base'
      require_relative 'features/authentication'
      require_relative 'features/account_management'
      require_relative 'features/security'
      require_relative 'features/mfa'
      require_relative 'features/passwordless'
      require_relative 'features/webauthn_config'
    end
  end
end
