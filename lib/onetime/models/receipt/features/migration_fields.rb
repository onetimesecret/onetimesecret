# lib/onetime/models/receipt/features/migration_fields.rb
#
# frozen_string_literal: true

# Receipt Migration Feature
#
# Adds Receipt-specific migration fields and methods for v1 → v2 migration.
# This feature should be removed after migration is complete.
#
# v1 → v2 CHANGES:
# - Model renamed: Metadata → Receipt
# - Key prefix: metadata:{id}:object → receipt:{objid}:object
# - custid (email or 'anon') → owner_id (Customer objid or 'anon')
# - New fields: org_id, domain_id for context tracking
# - Field renames: viewed → previewed, received → revealed
#
# REMOVAL: See lib/onetime/models/features/with_migration_fields.rb
#
module Onetime::Receipt::Features
  module MigrationFields
    Familia::Base.add_feature self, :receipt_migration_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Original v1 identifiers for reference/rollback
      base.field :v1_key       # Original metadata:{id}:object key
      base.field :v1_custid    # Original email-based custid or 'anon'
    end

    module ClassMethods
      # Find receipts that need owner_id migration
      #
      # @return [Array<Receipt>]
      def pending_owner_migration
        instances.revrangeraw(0, -1).collect do |identifier|
          receipt = load(identifier)
          receipt if receipt&.v1_custid.to_s.present? && receipt.owner_id.to_s.empty?
        end.compact
      end

      # Count anonymous vs authenticated receipts
      #
      # @return [Hash] { anonymous: count, authenticated: count }
      def ownership_stats
        stats = { anonymous: 0, authenticated: 0 }
        instances.revrangeraw(0, -1).each do |identifier|
          receipt = load(identifier)
          next unless receipt

          custid = receipt.v1_custid || receipt.owner_id
          if custid.to_s == 'anon' || custid.to_s.empty?
            stats[:anonymous] += 1
          else
            stats[:authenticated] += 1
          end
        end
        stats
      end
    end

    module InstanceMethods
      # Migrate custid to owner_id using customer email → objid lookup
      #
      # @param email_to_objid_mapping [Hash] email => customer_objid mapping
      # @param email_to_org_mapping [Hash] email => org_objid mapping (optional)
      # @return [Boolean] Success status
      def migrate_owner!(email_to_objid_mapping, email_to_org_mapping = {})
        return true if owner_id.to_s.present? # Already migrated

        custid = v1_custid
        return false if custid.to_s.empty?

        # Handle anonymous
        if custid == 'anon'
          self.owner_id         = 'anon'
          self.migration_status = 'completed'
          self.migrated_at      = Time.now.to_f.to_s
          return save
        end

        # Look up customer objid
        customer_objid = email_to_objid_mapping[custid]
        unless customer_objid
          OT.le '[Receipt.migrate_owner!] No customer found',
            { receipt: identifier, v1_custid: custid }
          return false
        end

        self.owner_id         = customer_objid
        self.migration_status = 'completed'
        self.migrated_at      = Time.now.to_f.to_s

        # Optionally set org_id if mapping provided
        org_objid   = email_to_org_mapping[custid]
        self.org_id = org_objid if org_objid

        save
      end

      # Migrate field names: viewed → previewed, received → revealed
      #
      # Copies values from deprecated fields to new canonical fields.
      #
      # @return [Boolean] Save result
      def migrate_field_names!
        # Only migrate if new fields are empty and old fields have values
        if previewed.to_s.empty? && viewed.to_s.present?
          self.previewed = viewed
        end

        if revealed.to_s.empty? && received.to_s.present?
          self.revealed = received
        end

        save
      end

      # Check if receipt needs owner migration
      #
      # @return [Boolean]
      def needs_owner_migration?
        v1_custid.to_s.present? && owner_id.to_s.empty?
      end

      # Check if receipt is from anonymous user
      #
      # @return [Boolean]
      def anonymous_receipt?
        owner_id.to_s == 'anon' || v1_custid.to_s == 'anon'
      end
    end
  end
end
