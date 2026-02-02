#!/usr/bin/env ruby
# migrations/2026-01-31/03_custom_domain_migration.rb
#
# frozen_string_literal: true

# CustomDomain Migration: v1 -> v2
#
# Transforms CustomDomain records to use organization ownership:
# - Key pattern: unchanged (custom_domain:{domainid}:object)
# - custid (email) -> org_id (Organization objid)
# - Add v1_custid to preserve original email
# - Add domain to organization's domains collection (Familia v2 participation)
#
# Usage:
#   bundle exec ruby migrations/2026-01-31/03_custom_domain_migration.rb           # Dry run
#   bundle exec ruby migrations/2026-01-31/03_custom_domain_migration.rb --run     # Actual run

require 'bundler/setup'
require 'familia/migration'

# Only boot if running directly (not via bin/ots migrate)
unless defined?(Onetime::CLI)
  require_relative '../../lib/onetime'
  OT.boot! :app
end

require_relative 'lib/migration_helper'

module OTS
  module Migration
    class CustomDomainMigration < Familia::Migration::Model
      self.migration_id = '20260131_03_custom_domain_migration'
      self.description = 'Migrate CustomDomain records to Organization ownership'
      self.dependencies = ['20260131_02_organization_generator']

      def prepare
        @model_class = Onetime::CustomDomain
        @batch_size = 100
        @migrated_at = Time.now.to_f.to_s

        # Build lookup mapping: email -> org_objid
        info "Building email to organization mapping..."
        @email_to_org = Helper.build_email_to_org_objid_mapping
        info "Found #{@email_to_org.size} email->org mappings"

        info "Total custom domains: #{@model_class.instances.size}"
      end

      def migration_needed?
        # Check if any domains have v1_custid but no org_id
        count = 0
        @model_class.instances.revrangeraw(0, 100).each do |identifier|
          domain = @model_class.find_by_identifier(identifier) rescue nil
          next unless domain

          # Needs migration if no org_id but has data suggesting v1 origin
          if domain.org_id.to_s.empty?
            count += 1
          end
        end

        info "Found #{count} domains potentially needing migration (sample of first 100)"
        count > 0
      end

      def process_record(obj, key)
        return unless obj

        # Already migrated (has org_id)
        if obj.org_id.to_s.present?
          track_stat(:skipped_already_migrated)
          return
        end

        # Need to find the owner's organization
        # In v1, domains had a custid field with email or were in owners hash
        v1_custid = find_v1_custid(obj)

        if v1_custid.to_s.empty?
          track_stat(:skipped_no_owner)
          warn "Domain #{obj.display_domain} has no identifiable owner"
          return
        end

        # Look up organization for this customer
        org_objid = @email_to_org[v1_custid]

        unless org_objid
          track_stat(:skipped_no_org_found)
          warn "No organization found for domain owner #{v1_custid}"
          return
        end

        for_realsies_this_time? do
          migrate_domain_to_org(obj, v1_custid, org_objid)
        end

        track_stat(:records_updated)
      end

      private

      def find_v1_custid(domain)
        # Check various places where owner info might be stored
        # 1. v1_custid field (if partially migrated)
        return domain.v1_custid if domain.v1_custid.to_s.present?

        # 2. Check owners class hash (legacy storage)
        if Onetime::CustomDomain.owners.key?(domain.domainid)
          owner_val = Onetime::CustomDomain.owners.get(domain.domainid)
          # In v1, this might be email; in v2 transition it could be org_id
          return owner_val if owner_val.to_s.include?('@')
        end

        # 3. Check if there's a custid field (very old v1)
        domain.respond_to?(:custid) ? domain.custid : nil
      end

      def migrate_domain_to_org(domain, v1_custid, org_objid)
        # Store original for rollback
        domain.store_original_record(
          domain.to_h,
          data_types_data: domain.snapshot_data_types,
          key: domain.dbkey,
          db: 6
        )

        # Update fields
        domain.org_id = org_objid
        domain.v1_custid = v1_custid
        domain.v1_identifier = v1_custid
        domain.migration_status = 'completed'
        domain.migrated_at = @migrated_at
        domain.save

        # Add to organization's domains collection via Familia v2 participation
        org = Onetime::Organization.load(org_objid)
        if org
          domain.add_to_organization_domains(org, Familia.now.to_f)
          track_stat(:org_participation_added)
          info "Migrated domain #{domain.display_domain} to org #{org.extid}"
        else
          warn "Could not load organization #{org_objid} for domain #{domain.display_domain}"
        end
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  exit(OTS::Migration::CustomDomainMigration.cli_run)
end
