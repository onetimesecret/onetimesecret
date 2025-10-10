# frozen_string_literal: true

module Auth
  module Config
    module Hooks
      module AccountLifecycle
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Custom account creation logic with Otto integration
            after_create_account do
              puts "New account created: #{account[:email]} (ID: #{account_id})"
              create_otto_customer
            end

            # Account closure with Otto customer cleanup
            after_close_account do
              puts "Account closed: #{account[:email]} (ID: #{account_id})"
              cleanup_otto_customer
            end
          end
        end

        private

        def create_otto_customer
          begin
            # Create or load customer using email as custid
            customer = if Onetime::Customer.exists?(account[:email])
              Onetime::Customer.load(account[:email])
            else
              Onetime::Customer.create!(account[:email])
            end
            puts "Created Otto customer: #{customer.custid} with extid: #{customer.extid}"

            # Store Otto's derived extid in Rodauth (NOT the objid!)
            DB[:accounts].where(id: account_id).update(external_id: customer.extid)
            puts "Linked Rodauth account #{account_id} to Otto extid: #{customer.extid}"

          rescue => e
            puts "Error creating Otto customer: #{e.message}"
            puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'
            # Don't fail account creation, but log the issue
          end
        end

        def cleanup_otto_customer
          begin
            if account[:external_id]
              customer = Onetime::Customer.find_by_extid(account[:external_id])
              if customer
                customer.destroy!
                puts "Deleted Otto customer: #{customer.custid} (extid: #{customer.extid})"
              else
                puts "Otto customer not found for extid: #{account[:external_id]}"
              end
            end
          rescue => e
            puts "Error cleaning up Otto customer: #{e.message}"
            puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'
            # Don't fail account closure, but log the issue
          end
        end
      end
    end
  end
end
