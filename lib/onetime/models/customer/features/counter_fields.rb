# apps/api/v2/models/customer/features/counter_fields.rb

module Onetime::Customer::Features
  module CounterFields
    Familia::Base.add_feature self, :counter_fields

    def self.included(base)
      OT.ld "[#{name}] Included in #{base}"
      base.include InstanceMethods

      base.field :secrets_created # regular hashkey string field
      base.field :secrets_burned
      base.field :secrets_shared
      base.field :emails_sent

      base.class_counter :secrets_created
      base.class_counter :secrets_shared
      base.class_counter :secrets_burned
      base.class_counter :emails_sent
    end

    module InstanceMethods
      def init_counter_fields
        # Initialze auto-increment fields. We do this since Redis
        # gets grumpy about trying to increment a hashkey field
        # that doesn't have any value at all yet. This is in
        # contrast to the regular INCR command where a
        # non-existant key will simply be set to 1.
        self.secrets_created ||= 0
        self.secrets_burned  ||= 0
        self.secrets_shared  ||= 0
        self.emails_sent     ||= 0
      end
    end
  end
end
