# lib/onetime/services/system/user_interface.rb

require_relative '../service_provider'

module Onetime
  module Services
    module System
      class SetupAuthentication < ServiceProvider
        # Process the authentication config to make
        # sure the settings make sense. For example,
        # the signup and signin flags should explicitly
        # be set to false if authentication is disabled.
      end
    end
  end
end
