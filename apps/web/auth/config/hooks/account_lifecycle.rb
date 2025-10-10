# frozen_string_literal: true

module Auth
  module Config
    module Hooks
      module AccountLifecycle
        def self.configure(rodauth_config)
          # Hooks have been moved to rodauth_main.rb for better method visibility
          # This file is kept for organizational reference but no longer configures hooks
          # See rodauth_main.rb for all account lifecycle hooks:
          # - after_create_account
          # - after_close_account
          # - after_verify_account
        end
      end
    end
  end
end
