# lib/onetime/models/customer/features/counter_fields.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  module CounterFields
    Familia::Base.add_feature self, :counter_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.include InstanceMethods

      # Store counters for each customer as separate keys. This allows for simple
      # math operations for aggregation and integrity checks, and avoids the need
      # for complex Lua scripts or loading entire hashkeys to manage hashkey fields.
      #
      # NOTE: Due to a limitation in Familia v2.1 declaring a field group for
      # related fields (i.e. separate db keys) does not work as expected. The
      # named group is empty. No runtime issues though so leaving it so it'll
      # just start working properly when the fix makes it in upstream.
      base.field_group :counters do
        base.counter :secrets_created
        base.counter :secrets_burned
        base.counter :secrets_shared
        base.counter :emails_sent
      end

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
