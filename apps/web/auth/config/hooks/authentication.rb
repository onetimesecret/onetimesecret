# frozen_string_literal: true

module Auth
  module Config
    module Hooks
      module Authentication
        def self.configure(rodauth_config)
          # Hooks have been moved to rodauth_main.rb for better method visibility
          # This file is kept for organizational reference but no longer configures hooks
          # See rodauth_main.rb for all authentication hooks:
          # - after_login
          # - before_logout
          # - after_logout
          # - after_reset_password_request
          # - after_reset_password
          # - after_change_password
        end
      end
    end
  end
end
