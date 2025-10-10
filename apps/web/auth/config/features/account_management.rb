# apps/web/auth/config/features/account_management.rb

module Auth
  module Config
    module Features
      module AccountManagement
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Account management features
            features = [:create_account, :close_account, :change_password, :reset_password]

            # Only enable verify_account in non-test environments
            features << :verify_account unless ENV['RACK_ENV'] == 'test'

            enable *features

            # Password requirements
            password_minimum_length 8
          end
        end
      end
    end
  end
end
