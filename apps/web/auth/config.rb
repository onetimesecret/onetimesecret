# apps/web/auth/config.rb

require_relative 'config/database'
require_relative 'config/email'
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
          Email.configure(self)

          # 4. Load and configure all hooks from modular files
          [
            Hooks::Validation.configure,
            Hooks::RateLimiting.configure,
            Hooks::AccountLifecycle.configure,
            Hooks::Authentication.configure,
            Hooks::SessionIntegration.configure,
            Hooks::ErrorLogging.configure,
          ].each do |hook_proc|
            instance_eval(&hook_proc)
          end
        end
    end
    end
  end
