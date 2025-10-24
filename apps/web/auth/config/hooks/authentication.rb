# frozen_string_literal: true

#
# apps/web/auth/config/hooks/authentication.rb
#
# This file defines the Rodauth hooks related to user authentication events,
# such as password changes and resets.
#

module Auth
  module Config
    module Hooks
      module Authentication
        #
        # Handlers
        #
        # This module contains the pure business logic for handling authentication events.
        #
        module Handlers
          # Updates customer metadata after a password change.
          #
          # @param account [Hash] The Rodauth account hash, containing :external_id.
          #
          def self.update_password_metadata(account)
            return unless account[:external_id]

            customer = Onetime::Customer.find_by_extid(account[:external_id])
            if customer
              customer.passphrase_updated = Familia.now.to_i
              customer.save
              OT.info "[authentication] Updated password metadata for customer: #{customer.custid}"
            else
              OT.info "[authentication] Customer not found for extid: #{account[:external_id]}"
            end
          end
        end

        #
        # Configuration
        #
        # This method returns a proc that Rodauth will execute to configure the
        # authentication event hooks.
        #
        def self.configure
          proc do
            #
            # Hook: After Password Reset Request
            #
            # This hook is triggered after a user requests a password reset.
            #
            after_reset_password_request do
              OT.info "[auth] Password reset requested for: #{account[:email]}"
            end

            #
            # Hook: After Password Reset
            #
            # This hook is triggered after a user successfully resets their password.
            #
            after_reset_password do
              OT.info "[auth] Password reset for: #{account[:email]}"
            end

            #
            # Hook: After Password Change
            #
            # This hook is triggered after a user changes their password. It updates
            # metadata in the associated Onetime::Customer record.
            #
            after_change_password do
              OT.info "[auth] Password changed for: #{account[:email]}"

              # Rodauth is the source of truth for password management. Here, we just
              # sync metadata to the customer record.
              Onetime::ErrorHandler.safe_execute('update_password_metadata', email: account[:email]) do
                Handlers.update_password_metadata(account)
              end
            end
          end
        end
      end
    end
  end
end
