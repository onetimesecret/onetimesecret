# lib/onetime/models/customer/features/status.rb

module V2::Customer::Features
  module Status
    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
      base.extend ClassMethods
      base.include InstanceMethods

      base.field :role
      base.field :verified
    end

    module ClassMethods
    end

    module InstanceMethods
      def verified?
        !anonymous? && verified.to_s.eql?('true')
      end

      def active?
        # We modify the role when destroying so if a customer is verified
        # and has a role of 'customer' then they are active.
        verified? && role?('customer')
      end

      def pending?
        # A customer is considered pending if they are not anonymous, not verified,
        # and have a role of 'customer'. If any one of these conditions is changes
        # then the customer is no longer pending.
        !anonymous? && !verified? && role?('customer') # we modify the role when destroying
      end
    end

    Familia::Base.add_feature self, :status
  end
end
