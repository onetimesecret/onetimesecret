# apps/web/core/controllers/account.rb

require_relative 'base'

module Core
  module Controllers
    class Account
      include Controllers::Base

      # Additional account-specific methods can be added here
      # Authentication methods have been moved to dedicated controllers
      # Welcome/billing methods have been moved to Welcome controller
    end
  end
end
