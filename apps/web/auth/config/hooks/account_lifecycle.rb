# frozen_string_literal: true

#
# apps/web/auth/config/hooks/account_lifecycle.rb
#
# This file defines the Rodauth hooks that trigger on account lifecycle
# events, such as creation, closure, and verification. It separates the
# business logic (e.g., creating a customer record) from the hook
# registration and error handling.
#

module Auth::Config::Hooks::AccountLifecycle
  #
  # Handlers
  #
  # This module contains the pure business logic for handling account events.
  # Each method is designed to be a self-contained unit of work, free from
  # error handling concerns, which are managed by the calling hooks.
  #
  module Handlers
    # Creates or loads a Customer record and links it to the Rodauth account.
    #
    # @param account_id [Integer] The ID of the Rodauth account.
    # @param account [Hash] The Rodauth account hash, containing at least :email.
    # @param db [Sequel::Database] The database connection.
    #
    def self.create_customer(account_id, account, db)
      # Use the account email as the customer identifier (custid).
      customer = if Onetime::Customer.exists?(account[:email])
                    Onetime::Customer.find_by_email(account[:email])
                  else
                    props = { email: account[:email], role: 'customer', verified: '1' }
                    Onetime::Customer.create!(**props)
                  end

      OT.info "[account-lifecycle] Created/loaded customer: #{customer.custid}"

      # Store the customer's external ID (extid) in the Rodauth accounts table
      # for future reference.
      rows_updated = db[:accounts].where(id: account_id).update(external_id: customer.extid)

      OT.info "[account-lifecycle] Linked Rodauth account #{account_id} to extid: #{customer.extid} (rows_updated: #{rows_updated})"

      # Verify the update
      stored_extid = db[:accounts].where(id: account_id).get(:external_id)
      OT.info "[account-lifecycle] Verification - stored external_id: #{stored_extid}"
    end

    # Deletes the Customer record associated with a closed Rodauth account.
    #
    # @param account [Hash] The Rodauth account hash, containing :external_id.
    #
    def self.delete_customer(account)
      return unless account[:external_id]

      customer = Onetime::Customer.find_by_extid(account[:external_id])
      if customer
        customer.destroy!
        OT.info "[account-lifecycle] Deleted customer: #{customer.custid} (extid: #{customer.extid})"
      else
        OT.info "[account-lifecycle] Customer not found for extid: #{account[:external_id]}"
      end
    end

    # Updates the Customer's verification status when the Rodauth account is verified.
    #
    # @param account [Hash] The Rodauth account hash, containing :external_id.
    #
    def self.verify_customer(account)
      return unless account[:external_id]

      customer = Onetime::Customer.find_by_extid(account[:external_id])
      if customer
        customer.verified = '1'
        customer.save
        OT.info "[account-lifecycle] Verified customer: #{customer.custid}"
      else
        OT.info "[account-lifecycle] Customer not found for extid: #{account[:external_id]}"
      end
    end
  end

  #
  # Configuration
  #
  # This method returns a proc that Rodauth will execute to configure the
  # account lifecycle hooks. Each hook wraps its corresponding handler call
  # in an error-safe execution block.
  #
  def self.configure
    proc do
      #
      # Hook: After Account Creation
      #
      # This hook is triggered after a new user successfully creates an account.
      # It ensures a corresponding Onetime::Customer record is created and linked.
      #
      after_create_account do
        OT.info "[auth] New account created: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Handlers.create_customer(account_id, account, Auth::Config::Database.connection)
        end
      end

      #
      # Hook: After Account Closure
      #
      # This hook is triggered when a user closes their account. It handles the
      # cleanup of the associated Onetime::Customer record.
      #
      after_close_account do
        OT.info "[auth] Account closed: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('delete_customer', account_id: account_id, extid: account[:extid]) do
          Handlers.delete_customer(account)
        end
      end

      #
      # Hook: After Account Verification
      #
      # This hook is triggered when a user verifies their account (e.g., by
      # clicking a link in an email). It updates the verification status of
      # the associated Onetime::Customer record.
      #
      # Note: This hook is disabled in the 'test' environment to simplify
      # testing scenarios that do not require email verification flows.
      #
      if ENV['RACK_ENV'] != 'test'
        after_verify_account do
          OT.info "[auth] Account verified: #{account[:extid]}"

          Onetime::ErrorHandler.safe_execute('verify_customer', extid: account[:extid]) do
            Handlers.verify_customer(account)
          end
        end
      end
    end
  end
end
