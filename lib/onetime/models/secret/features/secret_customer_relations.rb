# lib/onetime/models/secret/features/secret_customer_relations.rb

module V2::Secret::Features
  module SecretCustomerRelations
    Familia::Base.add_feature self, :secret_customer_relations

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

  end
end
