# frozen_string_literal: true

module Auth
  module Config
    module Hooks
      module Authentication
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Custom login logic with Otto integration
            after_login do
              puts "User logged in: #{account[:email]} from #{request.ip}"

              # Track login analytics or update last login time
              DB[:accounts].where(id: account_id).update(
                last_login_at: Sequel::CURRENT_TIMESTAMP,
                last_login_ip: request.ip
              )

              # Store identity information in session for Otto integration
              session['advanced_account_id'] = account_id
              session['account_external_id'] = account[:external_id]
              session['authenticated_at'] = Familia.now
            end

            # Handle login failures
            after_login_failure do
              puts "Login failure for: #{param('email')} from #{request.ip}"
            end
          end
        end
      end
    end
  end
end
