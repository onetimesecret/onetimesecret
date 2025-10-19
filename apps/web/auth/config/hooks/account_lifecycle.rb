# apps/web/auth/config/hooks/account_lifecycle.rb

module Auth::Config::Hooks::AccountLifecycle
  def self.configure
    proc do
      # Create customer when Rodauth account is created
      after_create_account do
        OT.info "[auth] New account created: #{account[:email]} (ID: #{account_id})"

        # Create customer inline
        begin
          # Create or load customer using email as custid
          customer = if Onetime::Customer.exists?(account[:email])
            Onetime::Customer.load(account[:email])
          else
            cust = Onetime::Customer.create!(email: account[:email], role: 'customer', verified: '1')
            cust
          end

          OT.info "[account-lifecycle] Created/loaded customer: #{customer.custid}"

          # Store derived extid in Rodauth
          db = Auth::Config::Database.connection
          db[:accounts].where(id: account_id).update(external_id: customer.extid)

          OT.info "[account-lifecycle] Linked Rodauth account #{account_id} to extid: #{customer.extid}"
        rescue StandardError => ex
          OT.le "[account-lifecycle] Error creating customer: #{ex.message}"
          OT.le ex.backtrace.join('') if Onetime.development?
          # Don't fail account creation
        end
      end

      # Cleanup customer when Rodauth account is closed
      after_close_account do
        OT.info "[auth] Account closed: #{account[:email]} (ID: #{account_id})"

        # Cleanup customer inline
        begin
          if account[:external_id]
            customer = Onetime::Customer.find_by_extid(account[:external_id])
            if customer
              customer.destroy!
              OT.info "[account-lifecycle] Deleted customer: #{customer.custid} (extid: #{customer.extid})"
            else
              OT.info "[account-lifecycle] customer not found for extid: #{account[:external_id]}"
            end
          end
        rescue StandardError => ex
          OT.le "[account-lifecycle] Error cleaning up customer: #{ex.message}"
          OT.le ex.backtrace.join('') if Onetime.development?
          # Don't fail account closure
        end
      end

      # Only configure verify_account hook if feature is enabled
      if ENV['RACK_ENV'] != 'test'
        after_verify_account do
          OT.info "[auth] Account verified: #{account[:email]}"

          # Update customer verification status if exists
          if account[:external_id]
            customer = Onetime::Customer.find_by_extid(account[:external_id])
            if customer
              customer.verified = '1'
              customer.save
            end
          end
        end
      end
    end
  end
end
