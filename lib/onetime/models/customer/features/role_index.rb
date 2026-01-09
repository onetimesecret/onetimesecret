# lib/onetime/models/customer/features/role_index.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  # Role-based indexing using Familia's multi_index feature.
  # Provides O(1) lookup of customers by role value.
  #
  # Redis keys: customer:role_index:{role_value}
  # Example: customer:role_index:colonel
  #
  # Usage:
  #   Customer.find_all_by_role('colonel')  # => [Customer, ...]
  #   Customer.role_index_for('colonel')    # => Familia::UnsortedSet
  #   Customer.colonel_count                # => Integer
  #
  module RoleIndex
    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Class-level multi-value index on role field
      # Creates UnsortedSet per role value (customer:role_index:colonel, etc.)
      # Provides find_all_by_role, sample_from_role, role_index_for
      base.multi_index :role, :role_index
    end

    module ClassMethods
      # Find first colonel by join date (oldest)
      # @return [Customer, nil]
      def find_first_colonel
        colonels = find_all_by_role('colonel')
        return nil if colonels.empty?

        colonels.min_by { |c| c.joined.to_i }
      end

      # List all colonels ordered by join date
      # @return [Array<Customer>]
      def list_colonels
        find_all_by_role('colonel').sort_by { |c| c.joined.to_i }
      end

      # Count colonels without loading objects
      # @return [Integer]
      def colonel_count
        role_index_for('colonel').size
      end
    end

    module InstanceMethods
      # Override save to handle role field changes
      # multi_index auto-adds to new role's index on save, but does NOT
      # auto-remove from old role's index, so we handle that explicitly.
      def save(**)
        # Track previous role for index update (only for existing records)
        previous_role = nil
        if exists?
          raw_role = dbclient.hget(dbkey, 'role')
          previous_role = raw_role ? JSON.parse(raw_role) : nil
        end

        result = super

        # If role changed, update the index (remove from old, already added to new by auto-index)
        if result && previous_role && previous_role != role.to_s
          update_in_class_role_index(previous_role)
        end

        result
      end

      # Override destroy to clean up role index
      def destroy!
        remove_from_class_role_index if role
        super
      end
    end

    Familia::Base.add_feature self, :role_index
  end
end
