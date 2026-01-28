# lib/onetime/models/organization/features/migration_fields.rb
#
# frozen_string_literal: true

# Organization Migration Feature
#
# Adds Organization-specific migration fields and methods for v1 → v2 migration.
# This feature should be removed after migration is complete.
#
# v1 → v2 CHANGES:
# - Organization is a NEW model (doesn't exist in v1)
# - Created 1:1 with Customer during migration
# - Receives billing fields from Customer (stripe_customer_id, etc.)
# - contact_email copied from Customer.email
#
# CABOOSE USAGE:
# The jsonkey :caboose stores migration metadata and payment link info:
# {
#   "migration": {
#     "source_customer_email": "user@example.com",
#     "migrated_at": 1706123456.789,
#     "v1_stripe_customer_id": "cus_xxx"
#   },
#   "payment_link": {
#     "plan": "identity",
#     "interval": "monthly",  # or "yearly"
#     "link_id": "plink_xxx"
#   }
# }
#
# REMOVAL: See lib/onetime/models/features/with_migration_fields.rb
#
module Onetime
  module Models
    module Features
      module OrganizationMigrationFields
        Familia::Base.add_feature self, :organization_migration_fields

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.extend ClassMethods
          base.include InstanceMethods

          # Track the source customer this org was created from
          base.field :v1_source_custid  # Email of customer this org was created from
        end

        module ClassMethods
          # Create organization from v1 customer data
          #
          # @param customer [Customer] The customer to create org for
          # @param v1_data [Hash] Original v1 customer data from dump
          # @return [Organization] The created organization
          def create_from_v1_customer!(customer, v1_data = {})
            raise Onetime::Problem, 'Customer required' unless customer

            # Check if org already exists for this customer
            existing_orgs = customer.organization_instances.to_a
            if existing_orgs.any?(&:is_default)
              org = existing_orgs.find(&:is_default)
              OT.info '[Organization.create_from_v1!] Using existing default org',
                { customer_extid: customer.extid, org_extid: org.extid }
              return org
            end

            email        = customer.email || v1_data[:custid] || v1_data['custid']
            display_name = "#{email.to_s.split('@').first}'s Workspace"

            org = create!(
              display_name,
              customer,
              email,
              is_default: true,
            )

            # Store v1 reference
            org.v1_source_custid = email

            # Copy billing fields from customer
            stripe_cust_id = v1_data[:stripe_customer_id] || v1_data['stripe_customer_id']
            stripe_sub_id  = v1_data[:stripe_subscription_id] || v1_data['stripe_subscription_id']

            if stripe_cust_id.to_s.present?
              org.stripe_customer_id     = stripe_cust_id
              org.stripe_subscription_id = stripe_sub_id
              org.stripe_checkout_email  = email
            end

            # Store migration metadata in caboose
            org.store_payment_link_info(v1_data)
            org.save

            OT.info '[Organization.create_from_v1!] Created org from v1 customer',
              {
                customer_extid: customer.extid,
                org_extid: org.extid,
                has_billing: stripe_cust_id.to_s.present?,
              }

            org
          end

          # Find organization by v1 source customer email
          #
          # @param email [String] Original v1 customer email
          # @return [Organization, nil]
          def find_by_v1_source(email)
            instances.revrangeraw(0, -1).each do |identifier|
              org = load(identifier)
              return org if org&.v1_source_custid == email
            end
            nil
          end
        end

        module InstanceMethods
          # Store payment link info for the customer's plan
          #
          # Payment-link subscriptions have different metadata than API-created.
          # We store the payment link info to help with future billing queries.
          #
          # @param v1_data [Hash] Original v1 customer data
          # @return [Boolean] Save result
          def store_payment_link_info(v1_data = {})
            # Determine plan from planid or default
            planid = v1_data[:planid] || v1_data['planid'] || self.planid
            return false if planid.to_s.empty? || planid == 'free' || planid == 'free_v1'

            # Parse plan info (e.g., "identity_plus_monthly" or "identity")
            # Note: In v0.23 customer data, planid values never had underscores.
            # Only "free" and "identity" were the available options.
            plan_parts = planid.to_s.split('_')
            plan_name  = plan_parts.first
            interval   = plan_parts.last if %w[monthly yearly].include?(plan_parts.last)
            interval ||= 'monthly' # Default to monthly for legacy "identity" planid

            data                 = caboose_hash || {}
            data['payment_link'] = {
              'plan' => plan_name,
              'interval' => interval,
              'migrated_from_v1' => true,
              'original_planid' => planid,
            }
            self.caboose         = data.to_json
            true
          end

          # Get payment link info from caboose
          #
          # @return [Hash, nil] Payment link info or nil
          def payment_link_info
            data = caboose_hash
            data&.dig('payment_link')
          end

          # Check if org was created from v1 migration
          #
          # @return [Boolean]
          def from_v1_migration?
            v1_source_custid.to_s.present? ||
              migration_metadata('source_customer_email').present?
          end

          # Store v1 migration source info in caboose
          #
          # @param customer_email [String] Original v1 customer email
          # @param stripe_customer_id [String, nil] Original stripe customer ID
          # @return [Boolean]
          def store_v1_source(customer_email, stripe_customer_id = nil)
            store_migration_metadata('source_customer_email', customer_email)
            store_migration_metadata('v1_stripe_customer_id', stripe_customer_id) if stripe_customer_id
            true
          end

          private

          # Parse caboose JSON to hash
          #
          # @return [Hash, nil]
          def caboose_hash
            return nil if caboose.to_s.empty?

            JSON.parse(caboose)
          rescue JSON::ParserError
            nil
          end
        end
      end
    end
  end
end
