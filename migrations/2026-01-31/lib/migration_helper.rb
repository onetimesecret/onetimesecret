# migrations/2026-01-31/lib/migration_helper.rb
#
# frozen_string_literal: true

# Shared utilities for OTS v1->v2 data migrations.
# Provides email->objid mappings and helper methods used across all migration modules.

module OTS
  module Migration
    module Helper
      class << self
        # Build email -> customer objid mapping for owner lookups
        #
        # @return [Hash] email => objid mapping
        def build_email_to_customer_objid_mapping
          mapping = {}
          Onetime::Customer.instances.revrangeraw(0, -1).each do |identifier|
            cust = Onetime::Customer.load(identifier)
            next unless cust

            # Use email field (v2) or v1_custid (migration marker)
            email = cust.email.to_s
            email = cust.v1_custid.to_s if email.empty?
            next if email.empty?

            mapping[email] = cust.objid
          end
          mapping
        end

        # Build email -> organization objid mapping for domain/receipt migrations
        #
        # Uses customer email to find their default organization's objid.
        #
        # @return [Hash] email => org_objid mapping
        def build_email_to_org_objid_mapping
          mapping = {}
          Onetime::Customer.instances.revrangeraw(0, -1).each do |identifier|
            cust = Onetime::Customer.load(identifier)
            next unless cust

            email = cust.email.to_s
            email = cust.v1_custid.to_s if email.empty?
            next if email.empty?

            # Find default org for this customer
            orgs = cust.organization_instances.to_a
            default_org = orgs.find { |o| o.is_default.to_s == 'true' }
            mapping[email] = default_org.objid if default_org
          end
          mapping
        end

        # Build customer objid -> organization objid mapping
        #
        # @return [Hash] customer_objid => org_objid mapping
        def build_customer_to_org_mapping
          mapping = {}
          Onetime::Customer.instances.revrangeraw(0, -1).each do |identifier|
            cust = Onetime::Customer.load(identifier)
            next unless cust

            orgs = cust.organization_instances.to_a
            default_org = orgs.find { |o| o.is_default.to_s == 'true' }
            mapping[cust.objid] = default_org.objid if default_org
          end
          mapping
        end

        # Check if a customer record appears to be already migrated
        #
        # @param cust [Onetime::Customer] Customer to check
        # @return [Boolean] true if appears migrated
        def customer_migrated?(cust)
          # Check for migration marker fields
          return true if cust.v1_custid.to_s.present?
          return true if cust.migration_status == 'completed'

          # Check if custid is a UUID (v2 pattern) vs email (v1 pattern)
          cust.custid.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end

        # Check if a record with owner_id appears migrated
        #
        # @param record [Familia::Horreum] Record with owner_id field
        # @return [Boolean] true if owner_id is set (migrated) or 'anon'
        def owner_migrated?(record)
          owner_id = record.owner_id.to_s
          return true if owner_id == 'anon'
          return false if owner_id.empty?

          # UUID format means already migrated
          owner_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end

        # Generate UUIDv7 from created timestamp for deterministic objid generation
        #
        # @param created_timestamp [Float, Integer, String] Unix timestamp
        # @return [String] UUIDv7 string
        def generate_uuid_v7_from_timestamp(created_timestamp)
          timestamp = created_timestamp.to_f
          timestamp = Time.now.to_f if timestamp <= 0

          # SecureRandom.uuid_v7 accepts timestamp: keyword in Ruby 3.4+
          if SecureRandom.respond_to?(:uuid_v7)
            SecureRandom.uuid_v7(timestamp: timestamp)
          else
            # Fallback: use Familia's generator if available
            Familia.generate_id
          end
        end

        # Format external ID from objid using model prefix
        #
        # @param objid [String] Object identifier (UUID)
        # @param prefix [String] Two-character prefix (e.g., 'ur', 'on', 'cd')
        # @return [String] External ID like 'ur1234567890'
        def format_extid(objid, prefix)
          # Use first 12 chars of objid without dashes for extid
          short_id = objid.to_s.delete('-')[0, 12]
          format('%<prefix>s%<id>s', prefix: prefix, id: short_id)
        end
      end
    end
  end
end
