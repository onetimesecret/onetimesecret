# lib/onetime/models/features/right_to_be_forgotten.rb

module Onetime
  module Models
    module Features
      module RightToBeForgotten
        Familia::Base.add_feature self, :right_to_be_forgotten

        using Familia::Refinements::TimeLiterals

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
        end

        module InstanceMethods
          # Marks the customer account as requested for destruction.
          #
          # This method doesn't actually destroy the customer record but prepares it
          # for eventual deletion after a grace period. It performs the following actions:
          #
          # 1. Sets a Time To Live (TTL) of 365 days on the customer record.
          # 2. Regenerates the API token.
          # 3. Clears the passphrase.
          # 4. Sets the verified status to 'false'.
          # 5. Changes the role to 'user_deleted_self'.
          #
          # The customer record is kept for a grace period to handle any remaining
          # account-related tasks, such as pro-rated refunds or sending confirmation
          # notifications.
          #
          # @return [void]
          def destroy_requested!
            destroy_requested
            save
          end

          def user_deleted_self?
            role?('user_deleted_self')
          end

          # Updates the customer record in memory for account deletion but
          # does not save the changes to the database. This separates the
          # modification process from the actual deletion which is a
          # helpful pattern for testing and debugging.
          #
          # Use #destroy_requested! for permanent deletion.
          def destroy_requested
            # NOTE: we don't use cust.destroy! here since we want to keep the
            # customer record around for a grace period to take care of any
            # remaining business to do with the account.
            #
            # We do however auto-expire the customer record after
            # the grace period.
            #
            # For example if we need to send a pro-rated refund
            # or if we need to send a notification to the customer
            # to confirm the account deletion.
            self.default_expiration = 365.days
            regenerate_apitoken
            self.passphrase         = ''
            self.verified           = 'false'
            self.role               = 'user_deleted_self'
            save
          end
        end

      end
    end
  end
end
