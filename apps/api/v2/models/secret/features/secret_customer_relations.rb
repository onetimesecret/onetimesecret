# apps/api/v2/models/secret/features/secret_customer_relations.rb

module V2
  module Models
    module Features
      module SecretCustomerRelations
        def self.included(base)
          OT.ld "[#{name}] Included in #{base}"
          base.extend ClassMethods
          base.include InstanceMethods
        end

        module ClassMethods
        end

        module InstanceMethods
          def load_customer
            cust = V2::Customer.load custid
            cust.nil? ? V2::Customer.anonymous : cust # TODO: Probably should simply return nil (see defensive "fix" in 23c152)
          end

          def anonymous?
            custid.to_s == 'anon'
          end

          def owner?(cust)
            !anonymous? && (cust.is_a?(V2::Customer) ? cust.custid : cust).to_s == custid.to_s
          end
        end

        Familia::Base.add_feature self, :secret_customer_relations
      end
    end
  end
end
