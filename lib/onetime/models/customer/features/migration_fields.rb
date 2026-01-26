# lib/onetime/models/customer/features/migration_fields.rb
#
# frozen_string_literal: true

# Customer Migration Feature
#
# Adds Customer-specific migration fields and methods for v1 → v2 migration.
# This feature should be removed after migration is complete.
#
# v1 → v2 CHANGES:
# - custid: email address → objid (UUID)
# - New: objid, extid (ur%<id>s format)
# - stripe_customer_id, stripe_subscription_id → Organization (deprecated here)
#
# REMOVAL: See lib/onetime/models/features/with_migration_fields.rb
#
module Onetime::Customer::Features
  module MigrationFields
    Familia::Base.add_feature self, :customer_migration_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # v1 email-based custid preserved for reference/rollback
      base.field :v1_custid  # Original email-based custid from v1
    end

    module ClassMethods
      # Build email → objid mapping for migration lookups
      #
      # @return [Hash] email => objid mapping
      def build_email_mapping
        mapping = {}
        instances.revrangeraw(0, -1).each do |identifier|
          cust = load(identifier)
          next unless cust

          email          = cust.email || cust.v1_custid
          mapping[email] = cust.objid if email
        end
        mapping
      end

      # Find customer by v1 email-based custid
      #
      # @param email [String] Email address used as custid in v1
      # @return [Customer, nil]
      def find_by_v1_custid(email)
        # First try email index (v2)
        cust = find_by_email(email)
        return cust if cust

        # Fallback: scan for v1_custid field
        instances.revrangeraw(0, -1).each do |identifier|
          cust = load(identifier)
          return cust if cust&.v1_custid == email
        end
        nil
      end
    end

    module InstanceMethods
      # Migrate billing fields to default organization
      #
      # Copies stripe_customer_id and stripe_subscription_id to the
      # customer's default organization. These fields are deprecated
      # on Customer and now live on Organization.
      #
      # @return [Organization, nil] The updated organization or nil if none
      def migrate_billing_to_organization!
        return nil if stripe_customer_id.to_s.empty?

        orgs = organization_instances.to_a
        org  = orgs.find(&:is_default)
        return nil unless org

        # Only migrate if org doesn't already have billing
        if org.stripe_customer_id.to_s.empty?
          org.stripe_customer_id     = stripe_customer_id
          org.stripe_subscription_id = stripe_subscription_id
          org.stripe_checkout_email  = email
          org.save

          OT.info '[Customer.migrate_billing!] Migrated billing to org',
            {
              customer_extid: extid,
              org_extid: org.extid,
              stripe_customer_id: stripe_customer_id,
            }
        end

        org
      end

      # Check if customer has v1 billing fields that need migration
      #
      # @return [Boolean]
      def needs_billing_migration?
        stripe_customer_id.to_s.present? || stripe_subscription_id.to_s.present?
      end
    end
  end
end
