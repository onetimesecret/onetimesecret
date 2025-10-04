# frozen_string_literal: true

require_relative 'hooks/authentication'
require_relative 'hooks/account_lifecycle'
require_relative 'hooks/otto_integration'

module Auth
  module Config
    module Hooks
      module All
        def self.configure(rodauth_config)
          Authentication.configure(rodauth_config)
          AccountLifecycle.configure(rodauth_config)
          OttoIntegration.configure(rodauth_config)
        end
      end
    end
  end
end
