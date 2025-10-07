# lib/onetime/models/secret/features/secret_customer_relations.rb

module Onetime::Secret::Features
  module SecretCustomerRelations
    Familia::Base.add_feature self, :secret_customer_relations

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods
    end

    module ClassMethods
    end

    module InstanceMethods
      def load_customer
        cust = Onetime::Customer.load custid
        cust.nil? ? Onetime::Customer.anonymous : cust # TODO: Probably should simply return nil (see defensive "fix" in 23c152)
      end

      def anonymous?
        custid.to_s == 'anon'
      end

      def owner?(cust)
        !anonymous? && (cust.is_a?(Onetime::Customer) ? cust.custid : cust).to_s == custid.to_s
      end
    end

  end
end
