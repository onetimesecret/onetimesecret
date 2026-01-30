# lib/onetime/models/custom_domain/features/migration_fields.rb
#
# frozen_string_literal: true

# CustomDomain Migration Feature
#
# Adds CustomDomain-specific migration fields and methods for v1 → v2 migration.
# This feature should be removed after migration is complete.
#
# v1 → v2 CHANGES:
# - custid (email) → org_id (Organization objid)
# - Owner lookup changes from Customer email to Organization objid
#
# REMOVAL: See lib/onetime/models/features/with_migration_fields.rb
#
module Onetime::CustomDomain::Features
  module MigrationFields
    Familia::Base.add_feature self, :custom_domain_migration_fields

    def self.included(base)
      OT.ld "[features] #{base}: #{name}"

      base.extend ClassMethods
      base.include InstanceMethods

      # Original v1 custid (email) for reference/rollback
      base.field :v1_custid  # Original email-based custid from v1
    end

    module ClassMethods
      # Find domains that need org_id migration
      #
      # Domains with v1_custid set but no org_id need migration.
      #
      # @return [Array<CustomDomain>]
      def pending_org_migration
        instances.revrangeraw(0, -1).collect do |identifier|
          domain = load(identifier)
          domain if domain&.v1_custid.to_s.present? && domain.org_id.to_s.empty?
        end.compact
      end

      # Build custid (email) → domainid mapping from v1 data
      #
      # @return [Hash] email => [domainid, domainid, ...] mapping
      def build_v1_owner_mapping
        mapping = Hash.new { |h, k| h[k] = [] }
        instances.revrangeraw(0, -1).each do |identifier|
          domain = load(identifier)
          next unless domain

          custid = domain.v1_custid || domain.org_id
          mapping[custid] << domain.domainid if custid
        end
        mapping
      end
    end

    module InstanceMethods
      # Migrate custid to org_id using customer → organization lookup
      #
      # @param email_to_org_mapping [Hash] email => org_objid mapping
      # @return [Boolean] Success status
      def migrate_to_org!(email_to_org_mapping)
        return true if org_id.to_s.present? # Already migrated

        email = v1_custid
        return false if email.to_s.empty?

        org_objid = email_to_org_mapping[email]
        unless org_objid
          OT.le '[CustomDomain.migrate_to_org!] No org found for email',
            { domain: display_domain, v1_custid: email }
          return false
        end

        # Set the new org_id
        self.org_id           = org_objid
        self.migration_status = 'completed'
        self.migrated_at      = Time.now.to_f.to_s
        save

        # Add to organization's domains participation
        org = Onetime::Organization.load(org_objid)
        if org
          add_to_organization_domains(org, Familia.now.to_f)
          OT.info '[CustomDomain.migrate_to_org!] Migrated domain to org',
            {
              domain: display_domain,
              org_extid: org.extid,
              v1_custid: email,
            }
        end

        true
      end

      # Check if domain needs org_id migration
      #
      # @return [Boolean]
      def needs_org_migration?
        v1_custid.to_s.present? && org_id.to_s.empty?
      end

      # Get the owning organization (v2) or nil
      #
      # @return [Organization, nil]
      def organization
        return nil if org_id.to_s.empty?

        Onetime::Organization.load(org_id)
      end
    end
  end
end
