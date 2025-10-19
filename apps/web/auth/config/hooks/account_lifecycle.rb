# apps/web/auth/config/hooks/account_lifecycle.rb

module Auth::Config::Hooks::AccountLifecycle
  # Pure business logic handlers - no error handling
  module Handlers
    # Creates or loads a Customer record and links it to the Rodauth account
    #
    # @param account_id [Integer] Rodauth account ID
    # @param account [Hash] Rodauth account hash with :email
    # @param db [Sequel::Database] Database connection
    def self.create_customer(account_id, account, db)
      # Create or load customer using email as custid
      customer = if Onetime::Customer.exists?(account[:email])
        Onetime::Customer.load(account[:email])
      else
        Onetime::Customer.create!(email: account[:email], role: 'customer', verified: '1')
      end

      OT.info "[account-lifecycle] Created/loaded customer: #{customer.custid}"

      # Store derived extid in Rodauth
      db[:accounts].where(id: account_id).update(external_id: customer.extid)

      OT.info "[account-lifecycle] Linked Rodauth account #{account_id} to extid: #{customer.extid}"
    end

    # Deletes the Customer record associated with a closed Rodauth account
    #
    # @param account [Hash] Rodauth account hash with :external_id
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

    # Updates Customer verification status when account is verified
    #
    # @param account [Hash] Rodauth account hash with :external_id
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

  def self.configure
    proc do
      # Create customer when Rodauth account is created
      after_create_account do
        OT.info "[auth] New account created: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Handlers.create_customer(account_id, account, Auth::Config::Database.connection)
        end
      end

      # Cleanup customer when Rodauth account is closed
      after_close_account do
        OT.info "[auth] Account closed: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('delete_customer', account_id: account_id, extid: account[:extid]) do
          Handlers.delete_customer(account)
        end
      end

      # Only configure verify_account hook if feature is enabled
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
