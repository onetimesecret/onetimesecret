#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 2: Organization Transformation
#
# Creates Organization records from V1 Customer records (1-for-1 mapping).
# Organization is a NEW model in V2 - no V1 Organization data exists.
#
# V1 Source:
#   customer:{email}:object  - Customer data used to generate Organization
#
# V2 Key Patterns:
#   organization:{objid}:object  - Hash: main organization data
#
# Transformations:
#   - Customer.objid -> owner_id
#   - Customer.email -> contact_email, billing_email
#   - Customer.stripe_* -> stripe_* (billing fields)
#   - Customer.planid -> planid
#   - Generate new objid/extid for Organization (UUIDv7 derived)
#   - display_name derived from email
#   - is_default = true for migrated orgs
#
# Output Lookup:
#   customer_to_org - Maps V1 customer objid to V2 organization objid
#
# Usage:
#   ruby transforms/02_organization_transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL file (default: exports/customer/customer_transformed.jsonl)
#   --output-dir=DIR    Output directory (default: exports/organization)
#   --dry-run           Parse and count without writing output
#   --help              Show help
#

require_relative '../lib/migration'

module Migration
  class OrganizationTransform < TransformerBase
    PHASE = 2
    MODEL_NAME = 'organization'

    # ExtID prefix for Organization model
    EXTID_PREFIX = 'on'

    def initialize
      super
      @customer_to_org = {}
      @email_to_org = {}
    end

    def default_stats
      super.merge(
        organizations_created: 0,
        customers_processed: 0,
        customers_skipped: 0,
        stripe_customers_linked: 0,
        stripe_subscriptions_linked: 0,
      )
    end

    def setup_defaults
      # Override to use customer_transformed.jsonl as input
      @options[:input_file] ||= 'exports/customer/customer_transformed.jsonl'
      @options[:output_dir] ||= 'exports/organization'
    end

    def validate_prerequisites!
      # Phase 2 requires Phase 1 (Customer) to be complete
      @manifest.validate_dependencies!(PHASE)

      # Load the email->customer lookup from Phase 1
      @lookup_registry.require_lookup(:email_to_customer, for_phase: PHASE)
    end

    # No grouping needed - each customer record creates one organization
    def grouping_key_for(record)
      nil
    end

    # Process a single transformed customer record
    def process_record(record)
      return [] if @options[:dry_run]

      key = record[:key]
      return [] unless key&.end_with?(':object')
      return [] unless key&.start_with?('customer:')

      @stats[:customers_processed] += 1

      # Decode the customer hash to get fields
      fields = restore_hash(record)
      unless fields
        track_error({ key: key }, 'Could not decode customer hash')
        @stats[:customers_skipped] += 1
        return []
      end

      customer_objid = record[:objid] || fields['objid']
      unless customer_objid && !customer_objid.empty?
        track_error({ key: key }, 'Customer missing objid')
        @stats[:customers_skipped] += 1
        return []
      end

      # Generate organization identifiers (derived from customer objid)
      org_objid = generate_org_objid(customer_objid)
      org_extid = generate_extid(org_objid, EXTID_PREFIX)

      # Build organization fields
      org_fields = build_organization_fields(fields, customer_objid, org_objid, org_extid, record)

      # Track mappings for downstream phases
      @customer_to_org[customer_objid] = org_objid
      email = fields['email'] || fields['v1_custid']
      @email_to_org[email] = org_objid if email

      # Track Stripe linkages
      @stats[:stripe_customers_linked] += 1 if org_fields['stripe_customer_id']&.length&.positive?
      @stats[:stripe_subscriptions_linked] += 1 if org_fields['stripe_subscription_id']&.length&.positive?

      # Create the V2 organization record
      v2_dump = create_dump(org_fields)
      @stats[:organizations_created] += 1

      [{
        key: "organization:#{org_objid}:object",
        type: 'hash',
        ttl_ms: -1, # Organizations don't expire
        db: record[:db],
        dump: v2_dump,
        objid: org_objid,
        extid: org_extid,
      }]
    end

    def register_outputs
      @lookup_registry.register(:customer_to_org, @customer_to_org, phase: PHASE)
      @lookup_registry.save(:customer_to_org)

      @lookup_registry.register(:email_to_org, @email_to_org, phase: PHASE)
      @lookup_registry.save(:email_to_org)

      puts "Registered #{@customer_to_org.size} customer->org mappings"
      puts "Registered #{@email_to_org.size} email->org mappings"
    end

    def print_custom_stats
      puts
      puts 'Organization Generation Stats:'
      puts "  Customers processed: #{@stats[:customers_processed]}"
      puts "  Organizations created: #{@stats[:organizations_created]}"
      puts "  Customers skipped: #{@stats[:customers_skipped]}"
      puts
      puts 'Stripe Linkages:'
      puts "  Stripe customers linked: #{@stats[:stripe_customers_linked]}"
      puts "  Stripe subscriptions linked: #{@stats[:stripe_subscriptions_linked]}"
    end

    private

    def build_organization_fields(customer_fields, customer_objid, org_objid, org_extid, source_record)
      email = customer_fields['email'] || customer_fields['v1_custid']

      {
        # Identifiers
        'objid' => org_objid,
        'extid' => org_extid,

        # Owner reference (the customer who owns this org)
        'owner_id' => customer_objid,

        # Contact info (both default to customer email)
        'contact_email' => email,
        'billing_email' => email,

        # Stripe billing fields (transferred from customer)
        'stripe_customer_id' => customer_fields['stripe_customer_id'] || '',
        'stripe_subscription_id' => customer_fields['stripe_subscription_id'] || '',
        'planid' => customer_fields['planid'] || 'anonymous',

        # Default org settings
        'display_name' => derive_display_name(email),
        'description' => '',
        'is_default' => 'true',
        'subscription_status' => derive_subscription_status(customer_fields),

        # Timestamps
        'created' => customer_fields['created'] || Time.now.to_f.to_s,
        'updated' => Time.now.to_f.to_s,

        # Migration tracking
        'v1_identifier' => source_record[:key],
        'v1_source_custid' => email,
        'migration_status' => 'completed',
        'migrated_at' => Time.now.to_f.to_s,
        '_original_record' => JSON.generate(customer_fields),
      }
    end

    # Generate a deterministic org objid from customer objid
    # Uses a namespace-based approach for reproducibility
    def generate_org_objid(customer_objid)
      require 'digest'

      # Create a deterministic UUID-like objid derived from customer
      # Using SHA256 and taking first 32 hex chars (similar to UUIDv5 approach)
      namespace = 'organization-from-customer'
      digest = Digest::SHA256.hexdigest("#{namespace}:#{customer_objid}")
      digest[0, 32]
    end

    # Generate extid from objid with prefix (e.g., "on" + 25 base36 chars)
    def generate_extid(objid, prefix)
      # Convert hex objid to integer, then to base36
      # Truncate/pad to 25 chars for consistent length
      int_val = objid.to_i(16)
      base36 = int_val.to_s(36)

      # Pad or truncate to exactly 25 characters
      if base36.length < 25
        base36 = base36.rjust(25, '0')
      elsif base36.length > 25
        base36 = base36[0, 25]
      end

      "#{prefix}#{base36}"
    end

    # Derive a display name from email (use local part, titleized)
    def derive_display_name(email)
      return 'Unknown Organization' unless email

      local_part = email.split('@').first
      # Convert underscores/dots to spaces, titleize
      local_part.gsub(/[._]/, ' ').split.map(&:capitalize).join(' ')
    end

    # Derive subscription status from customer fields
    def derive_subscription_status(customer_fields)
      if customer_fields['stripe_subscription_id']&.length&.positive?
        'active'
      elsif customer_fields['planid'] && customer_fields['planid'] != 'anonymous'
        'active'
      else
        'none'
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Migration::OrganizationTransform.new.run(ARGV)
end
