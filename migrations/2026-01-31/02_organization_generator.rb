#!/usr/bin/env ruby
# migrations/2026-01-31/02_organization_generator.rb
#
# frozen_string_literal: true

# Organization Generator: Create from v1 Customers
#
# Organizations are NEW in v2 - they don't exist in v1.
# This migration creates one default Organization per Customer.
#
# Key pattern: organization:{objid}:object
# Fields:
#   - objid: UUID
#   - extid: 'on%<id>s' format
#   - owner_id: Customer objid
#   - is_default: 'true'
#   - contact_email: Customer email
#   - v1_source_custid: Original customer email (for rollback)
#   - stripe_customer_id, stripe_subscription_id: From Customer billing
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/02_organization_generator.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/02_organization_generator.rb --run     # Actual run

require 'bundler/setup'

# Only boot if running directly (not via bin/ots migrate)
unless defined?(Onetime::CLI)
  require_relative '../../lib/onetime'
  OT.boot! :app
end

require_relative 'lib/migration_helper'

module OTS
  module Migration
    class OrganizationGenerator < Familia::Migration::Model
      self.migration_id = '20260131_02_organization_generator'
      self.description = 'Generate Organization records from Customer data'
      self.dependencies = ['20260131_01_customer_migration']

      def prepare
        @model_class = Onetime::Customer
        @batch_size = 100
        @migrated_at = Time.now.to_f.to_s
        @organizations_created = 0

        info "Preparing Organization generation..."
        info "Total customers: #{@model_class.instances.size}"
        info "Existing organizations: #{Onetime::Organization.instances.size}"
      end

      def migration_needed?
        # Check if any customers lack a default organization
        customers_without_org = 0
        @model_class.instances.revrangeraw(0, 100).each do |identifier|
          cust = @model_class.load(identifier) rescue nil
          next unless cust
          next if cust.anonymous?

          orgs = cust.organization_instances.to_a rescue []
          has_default = orgs.any? { |o| o.is_default.to_s == 'true' }
          customers_without_org += 1 unless has_default
        end

        info "Found #{customers_without_org} customers without default org (sample of first 100)"
        customers_without_org > 0
      end

      def process_record(obj, key)
        return unless obj

        # Skip anonymous
        if obj.anonymous?
          track_stat(:skipped_anonymous)
          return
        end

        # Check if customer already has a default organization
        orgs = obj.organization_instances.to_a rescue []
        existing_default = orgs.find { |o| o.is_default.to_s == 'true' }

        if existing_default
          track_stat(:skipped_has_org)
          debug("Customer #{obj.extid} already has default org #{existing_default.extid}")
          return
        end

        # Generate organization for this customer
        for_realsies_this_time? do
          create_organization_for_customer(obj)
        end

        track_stat(:records_updated)
      end

      private

      def create_organization_for_customer(cust)
        email = cust.email.to_s
        email = cust.v1_custid.to_s if email.empty?

        if email.empty?
          track_stat(:skipped_no_email)
          warn "Customer #{cust.objid} has no email - cannot create org"
          return
        end

        # Generate deterministic objid from customer's created timestamp
        # Offset by 1 second to avoid collision with customer objid
        created = cust.created.to_f + 1
        org_objid = Helper.generate_uuid_v7_from_timestamp(created)
        org_extid = Helper.format_extid(org_objid, 'on')

        # Build display name from email
        local_part = email.split('@').first
        display_name = "#{local_part}'s Workspace"

        org = Onetime::Organization.new(
          objid: org_objid,
          extid: org_extid,
          display_name: display_name,
          owner_id: cust.objid,
          contact_email: email,
          is_default: 'true',

          # Migration tracking
          v1_source_custid: email,
          v1_identifier: email,
          migration_status: 'completed',
          migrated_at: @migrated_at,
        )

        # Copy billing fields from customer (deprecated on Customer, now on Org)
        if cust.respond_to?(:stripe_customer_id) && cust.stripe_customer_id.to_s.present?
          org.stripe_customer_id = cust.stripe_customer_id
          track_stat(:billing_migrated)
        end

        if cust.respond_to?(:stripe_subscription_id) && cust.stripe_subscription_id.to_s.present?
          org.stripe_subscription_id = cust.stripe_subscription_id
        end

        if cust.respond_to?(:stripe_checkout_email) && cust.stripe_checkout_email.to_s.present?
          org.stripe_checkout_email = cust.stripe_checkout_email
        end

        # Store payment link info if planid present
        store_payment_link_info(org, cust)

        # Save the organization
        org.save

        # Add customer as member with owner role using Familia v2 participation
        org.add_members_instance(cust, through_attrs: { role: 'owner' })

        @organizations_created += 1
        track_stat(:organizations_created)
        info "Created org #{org.extid} for customer #{cust.extid}"
      end

      def store_payment_link_info(org, cust)
        planid = cust.planid.to_s
        return if planid.empty? || planid == 'free' || planid == 'free_v1'

        # Parse plan info (e.g., "identity" or "identity_monthly")
        plan_parts = planid.split('_')
        plan_name = plan_parts.first
        interval = plan_parts.last if %w[monthly yearly].include?(plan_parts.last)
        interval ||= 'monthly'

        org.store_payment_link_info({
          'planid' => planid,
          'plan' => plan_name,
          'interval' => interval,
          'migrated_from_v1' => true,
        })

        track_stat(:payment_link_migrated)
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::OrganizationGenerator.cli_run)
end
