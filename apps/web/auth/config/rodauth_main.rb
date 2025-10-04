# frozen_string_literal: true

require_relative 'database'
require_relative 'features'
require_relative 'hooks'
require_relative 'email'

module Auth
  module Config
    module RodauthMain
      def self.configure
        proc do
          # Apply feature configurations
          Features::Base.configure(self)
          Features::Authentication.configure(self)
          Features::AccountManagement.configure(self)
          Features::Security.configure(self)
          Features::MFA.configure(self)

          # Apply email configuration
          Email.configure(self)

          # Apply all hooks
          Hooks::All.configure(self)
        end
      end
    end
  end
end
