#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 3: CustomDomain Transformation
#
# Transforms V1 customdomain records to V2 format with proper identifiers.
# Domains are now associated with organizations, not customers directly.
#
# V1 Key Patterns:
#   customdomain:{domainid}             - Hash: main domain data
#   customdomain:{domainid}:brand       - Hash: brand settings
#   customdomain:{domainid}:logo        - Hash: logo settings
#   customdomain:{domainid}:icon        - Hash: icon settings
#
# V2 Key Patterns:
#   custom_domain:{objid}:object        - Hash: main domain data
#   custom_domain:{objid}:brand         - Hash: brand settings
#   custom_domain:{objid}:logo          - Hash: logo settings
#   custom_domain:{objid}:icon          - Hash: icon settings
#
# Transformations:
#   - Key prefix: customdomain -> custom_domain (underscore added)
#   - custid (email) -> org_id (via email->customer->org lookups)
#   - objid = domainid (aliased)
#   - extid = "cd" + domainid[0..7]
#   - Migration tracking fields added
#
# Output Lookup:
#   fqdn_to_domain - Maps display_domain (FQDN) to domain objid
#
# Usage:
#   ruby transforms/03_custom_domain_transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: results/customdomain_dump.jsonl)
#   --output-dir=DIR    Output directory (default: results)
#   --dry-run           Parse and count without writing output
#   --help              Show help
#

require_relative '../lib/migration'

module Migration
  class CustomDomainTransform < TransformerBase
    PHASE = 3
    MODEL_NAME = 'custom_domain'

    # ExtID prefix for CustomDomain model
    EXTID_PREFIX = 'cd'

    def initialize
      super
      @fqdn_to_domain = {}
      @email_to_customer = nil
      @customer_to_org = nil
    end

    def default_stats
      super.merge(
        groups_processed: 0,
        related_records: 0,
        transformed_objects: 0,
        brand_records: 0,
        logo_records: 0,
        icon_records: 0,
        domains_skipped: 0,
        org_lookup_failures: 0,
      )
    end

    def setup_defaults
      # Override to use customdomain dump as input (V1 naming)
      results_dir = @options[:results_dir]
      @options[:input_file] ||= File.join(results_dir, 'customdomain_dump.jsonl')
      @options[:output_dir] ||= results_dir
    end

    def validate_prerequisites!
      # Phase 3 requires Phase 1 and Phase 2 to be complete
      @manifest.validate_dependencies!(PHASE)

      # Load required lookups from earlier phases
      @email_to_customer = @lookup_registry.require_lookup(:email_to_customer, for_phase: PHASE)
      @customer_to_org = @lookup_registry.require_lookup(:customer_to_org, for_phase: PHASE)
    end

    # Group by domainid: "customdomain:{domainid}:*" -> domainid
    def grouping_key_for(record)
      key = record[:key]
      return nil unless key&.start_with?('customdomain:')

      parts = key.split(':')
      return nil if parts.size < 2

      parts[1]
    end

    # Process all records for a single domain together
    def process_group(domainid, records)
      return [] if @options[:dry_run]

      # Find the main object record (may be suffix-less or :object)
      object_record = records.find { |r| r[:key] == "customdomain:#{domainid}" } ||
                      records.find { |r| r[:key]&.end_with?(':object') }

      unless object_record
        track_error({ domainid: domainid }, 'No main record found in group')
        @stats[:domains_skipped] += 1
        return []
      end

      # Separate related records
      related_records = records.reject { |r| r == object_record }

      # Batch decode all hash records
      hash_records = records.select { |r| r[:type] == 'hash' }
      decoded_fields = {}

      @redis_helper.batch_restore_hashes(hash_records) do |record, fields|
        decoded_fields[record[:key]] = fields
      end

      # Get fields from the object record
      object_fields = decoded_fields[object_record[:key]] || {}

      # Resolve identifiers
      objid = domainid
      extid = "#{EXTID_PREFIX}#{domainid[0..7]}"

      # Resolve org_id from custid (email) via lookups
      custid = object_fields['custid']
      org_id = resolve_org_id(custid)

      unless org_id
        @stats[:org_lookup_failures] += 1
        track_error({ domainid: domainid, custid: custid }, 'Could not resolve org_id from custid')
        # Continue anyway - domain can exist without org linkage
      end

      # Track fqdn -> objid for downstream phases
      display_domain = object_fields['display_domain']
      @fqdn_to_domain[display_domain] = objid if display_domain

      # Transform all records
      v2_records = []

      # Transform the main object
      v2_object = transform_domain_object(object_record, object_fields, objid, extid, org_id)
      v2_records << v2_object
      @stats[:transformed_objects] += 1

      # Transform related records
      related_records.each do |record|
        v2_record = transform_related_record(record, objid, decoded_fields[record[:key]])
        v2_records << v2_record if v2_record
      end

      v2_records
    end

    # Fallback for ungrouped records
    def process_record(record)
      key = record[:key]
      return [] unless key&.start_with?('customdomain:')

      warn "Warning: CustomDomain record processed outside group: #{key}"
      []
    end

    def register_outputs
      @lookup_registry.register(:fqdn_to_domain, @fqdn_to_domain, phase: PHASE)
      @lookup_registry.save(:fqdn_to_domain)

      puts "Registered #{@fqdn_to_domain.size} fqdn->domain mappings"
    end

    def print_custom_stats
      puts
      puts 'Transformation Stats:'
      puts "  Groups processed: #{@stats[:groups_processed]}"
      puts "  Transformed objects: #{@stats[:transformed_objects]}"
      puts "  Related records: #{@stats[:related_records]}"
      puts "  Domains skipped: #{@stats[:domains_skipped]}"
      puts
      puts 'Related Record Types:'
      puts "  Brand records: #{@stats[:brand_records]}"
      puts "  Logo records: #{@stats[:logo_records]}"
      puts "  Icon records: #{@stats[:icon_records]}"
      puts
      puts 'Lookup Stats:'
      puts "  Org lookup failures: #{@stats[:org_lookup_failures]}"
    end

    private

    def resolve_org_id(custid)
      return nil unless custid

      # custid is an email -> lookup customer objid -> lookup org objid
      customer_objid = @email_to_customer[custid]
      return nil unless customer_objid

      @customer_to_org[customer_objid]
    end

    def transform_domain_object(v1_record, v1_fields, objid, extid, org_id)
      v2_fields = v1_fields.dup

      # Set canonical identifiers
      v2_fields['objid'] = objid
      v2_fields['extid'] = extid

      # custid (email) -> org_id, preserving original
      v2_fields['v1_custid'] = v2_fields['custid'] if v2_fields['custid']
      v2_fields['org_id'] = org_id if org_id
      v2_fields.delete('custid')

      # Add migration tracking fields
      v2_fields['v1_identifier'] = v1_record[:key]
      v2_fields['migration_status'] = 'completed'
      v2_fields['migrated_at'] = Time.now.to_f.to_s
      v2_fields['_original_record'] = JSON.generate(v1_fields)

      v2_dump_b64 = create_dump(v2_fields)

      {
        key: "custom_domain:#{objid}:object",
        type: 'hash',
        ttl_ms: v1_record[:ttl_ms],
        db: v1_record[:db],
        dump: v2_dump_b64,
        objid: objid,
        extid: extid,
      }
    end

    def transform_related_record(record, objid, fields)
      key = record[:key]
      parts = key.split(':')
      suffix = parts.last if parts.size > 2

      case suffix
      when 'brand'
        transform_hash_record(record, objid, 'brand', fields)
      when 'logo'
        transform_hash_record(record, objid, 'logo', fields)
      when 'icon'
        transform_hash_record(record, objid, 'icon', fields)
      else
        transform_generic_related(record, objid, suffix)
      end
    end

    def transform_hash_record(record, objid, suffix, fields)
      stat_key = "#{suffix}_records".to_sym
      @stats[stat_key] += 1 if @stats.key?(stat_key)

      return nil unless fields

      v2_dump = create_dump(fields)
      {
        key: "custom_domain:#{objid}:#{suffix}",
        type: 'hash',
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: v2_dump,
      }
    end

    def transform_generic_related(record, objid, suffix)
      warn "Warning: Unknown related record type: #{suffix} for custom_domain #{objid}"

      {
        key: "custom_domain:#{objid}:#{suffix}",
        type: record[:type],
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: record[:dump],
      }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Migration::CustomDomainTransform.new.run(ARGV)
end
