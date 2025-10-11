# apps/web/auth/config/hooks/account_lifecycle.rb

module Auth
  module Config
    module Hooks
      module AccountLifecycle
        def self.configure
          proc do
            # Create Otto customer when Rodauth account is created
            after_create_account do
              OT.info "[auth] New account created: #{account[:email]} (ID: #{account_id})"

              # Create Otto customer inline
              begin
                # Create or load customer using email as custid
                customer = if Onetime::Customer.exists?(account[:email])
                  Onetime::Customer.load(account[:email])
                else
                  cust = Onetime::Customer.create! email: account[:email]
                  cust.update_passphrase('') # Rodauth manages password
                  cust.role = 'customer'
                  cust.verified = '1' # Rodauth handles verification
                  cust.save
                  cust
                end

                OT.info "[otto-integration] Created/loaded customer: #{customer.custid}"

                # Store Otto's derived extid in Rodauth
                db = Auth::Config::Database.connection
                db[:accounts].where(id: account_id).update(external_id: customer.extid)
                OT.info "[otto-integration] Linked Rodauth account #{account_id} to Otto extid: #{customer.extid}"
              rescue => e
                OT.le "[otto-integration] Error creating Otto customer: #{e.message}"
                OT.le e.backtrace.join("
") if Onetime.development?
                # Don't fail account creation
              end
            end

            # Cleanup Otto customer when Rodauth account is closed
            after_close_account do
              OT.info "[auth] Account closed: #{account[:email]} (ID: #{account_id})"

              # Cleanup Otto customer inline
              begin
                if account[:external_id]
                  customer = Onetime::Customer.load_by_extid(account[:external_id])
                  if customer
                    customer.destroy!
                    OT.info "[otto-integration] Deleted Otto customer: #{customer.custid} (extid: #{customer.extid})"
                  else
                    OT.info "[otto-integration] Otto customer not found for extid: #{account[:external_id]}"
                  end
                end
              rescue => e
                OT.le "[otto-integration] Error cleaning up Otto customer: #{e.message}"
                OT.le e.backtrace.join("
") if Onetime.development?
                # Don't fail account closure
              end
            end

            # Only configure verify_account hook if feature is enabled
            if ENV['RACK_ENV'] != 'test'
              after_verify_account do
                OT.info "[auth] Account verified: #{account[:email]}"

                # Update Otto customer verification status if exists
                if account[:external_id]
                  customer = Onetime::Customer.load_by_extid(account[:external_id])
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
    end
  end
end
