# lib/onetime/models/customer/features/colonel_tracking.rb
#
# frozen_string_literal: true

module Onetime::Customer::Features
  # Maintains a class-level sorted set of customer IDs with role='colonel'
  # for efficient colonel lookups without scanning all customers.
  #
  # The sorted set uses assignment timestamp as score for:
  # - Chronological ordering (find oldest/newest colonels)
  # - Audit trail (when was role assigned)
  #
  # Performance improvement: O(1) lookups instead of O(n) scanning all customers.
  #
  module ColonelTracking
    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Track colonels in a class-level sorted set
      # Score = timestamp when colonel role was assigned
      base.class_sorted_set :colonels
    end

    module ClassMethods
      # Find first colonel (oldest by assignment timestamp)
      # @return [Customer, nil] First colonel or nil if none exist
      def find_first_colonel
        # Get oldest colonel ID (lowest score)
        # Use range() not rangeraw() to get decoded values
        colonel_id = colonels.range(0, 0).first
        return nil unless colonel_id

        load(colonel_id)
      rescue Familia::RecordNotFound
        # Colonel was deleted but not removed from set - clean up
        colonels.remove_element(colonel_id)
        find_first_colonel # Retry with next oldest
      end

      # List all colonels ordered by assignment time
      # @return [Array<Customer>] Array of colonel customers
      def list_colonels
        # Use members to get decoded values
        colonel_ids = colonels.members
        colonel_ids.filter_map { |id| load(id) rescue nil }
      end

      # Count colonels without loading them
      # @return [Integer] Number of colonels
      def colonel_count
        colonels.size
      end

      # Sync colonel catalog from database
      # Useful for migrations or recovering from inconsistent state
      # @param dry_run [Boolean] If true, only report what would be done
      # @return [Hash] Summary of sync operation
      def sync_colonel_catalog(dry_run: false)
        summary = { added: 0, removed: 0, unchanged: 0, scanned: 0 }

        # Find all current colonels by scanning
        current_colonels = Set.new
        instances.all.each do |custid|
          summary[:scanned] += 1
          customer = load(custid) rescue nil
          next unless customer

          current_colonels.add(custid) if customer.role.to_s == 'colonel'
        end

        # Get catalog state (use members for decoded values)
        catalog_colonels = Set.new(colonels.members)

        # Add missing colonels to catalog
        (current_colonels - catalog_colonels).each do |custid|
          summary[:added] += 1
          unless dry_run
            customer = load(custid)
            score = customer.joined.to_i > 0 ? customer.joined.to_i : Familia.now.to_i
            colonels.add(custid, score)
          end
        end

        # Remove stale entries from catalog
        (catalog_colonels - current_colonels).each do |custid|
          summary[:removed] += 1
          colonels.remove_element(custid) unless dry_run
        end

        summary[:unchanged] = (current_colonels & catalog_colonels).size
        summary
      end
    end

    module InstanceMethods
      # Override save to maintain colonel tracking
      def save(**)
        # Track previous role state before save (only for existing records)
        previous_role = nil
        if exists?
          # Redis stores values as JSON-encoded strings, need to parse
          raw_role = dbclient.hget(dbkey, 'role')
          previous_role = raw_role ? JSON.parse(raw_role) : nil
        end

        result = super

        # Update colonel tracking after successful save
        update_colonel_catalog(previous_role) if result

        result
      end

      # Override destroy! to clean up colonel catalog
      def destroy!
        # Remove from colonel catalog before destroying
        self.class.colonels.remove_element(identifier) if role.to_s == 'colonel'

        super
      end

      private

      # Update colonel catalog based on role changes
      # Called automatically after save
      def update_colonel_catalog(previous_role)
        current_is_colonel = role.to_s == 'colonel'
        previous_was_colonel = previous_role.to_s == 'colonel'

        if current_is_colonel && !previous_was_colonel
          # Add to colonel catalog with current timestamp as score
          self.class.colonels.add(identifier, Familia.now.to_f)
          OT.ld "[ColonelTracking] Added to catalog: #{custid}"
        elsif !current_is_colonel && previous_was_colonel
          # Remove from colonel catalog
          self.class.colonels.remove_element(identifier)
          OT.ld "[ColonelTracking] Removed from catalog: #{custid}"
        end
      end
    end

    Familia::Base.add_feature self, :colonel_tracking
  end
end
