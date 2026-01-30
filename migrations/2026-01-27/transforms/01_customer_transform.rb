#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 1: Customer Transformation
#
# Transforms V1 customer records to V2 format with proper identifiers.
# This is the first phase - downstream phases depend on the email->objid lookup.
#
# V1 Key Patterns:
#   customer:{email}:object       - Hash: main customer data
#   customer:{email}:metadata     - SortedSet: purchase receipts (renamed in V2)
#   customer:{email}:feature_flags - Hash: enabled features
#
# V2 Key Patterns:
#   customer:{objid}:object       - Hash: main customer data
#   customer:{objid}:receipts     - SortedSet: purchase receipts (renamed from :metadata)
#   customer:{objid}:feature_flags - Hash: enabled features
#
# Transformations:
#   - Key prefix: email -> objid
#   - custid field: email -> objid (original preserved as v1_custid)
#   - :metadata suffix -> :receipts (semantic rename)
#   - Migration tracking fields added
#
# Output Lookup:
#   email_to_customer - Maps V1 email identifiers to V2 objids
#
# Usage:
#   ruby transforms/01_customer_transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: exports/customer/customer_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports/customer)
#   --dry-run           Parse and count without writing output
#   --help              Show help
#

require_relative '../lib/migration'

module Migration
  class CustomerTransform < TransformerBase
    PHASE = 1
    MODEL_NAME = 'customer'

    # ExtID prefix for Customer model
    EXTID_PREFIX = 'ur'

    def initialize
      super
      @email_to_objid = {}
    end

    def default_stats
      super.merge(
        groups_processed: 0,
        related_records: 0,
        transformed_objects: 0,
        renamed_metadata_to_receipts: 0,
        feature_flags_processed: 0,
        sorted_sets_processed: 0,
        customers_skipped: 0,
      )
    end

    def validate_prerequisites!
      # Phase 1 has no prerequisites - it's the first phase
      @manifest.validate_dependencies!(PHASE)
    end

    # Group by customer email: "customer:{email}:*" -> email
    def grouping_key_for(record)
      key = record[:key]
      return nil unless key&.start_with?('customer:')

      parts = key.split(':')
      return nil if parts.size < 3

      parts[1]
    end

    # Process all records for a single customer together
    def process_group(email, records)
      return [] if @options[:dry_run]

      # Find the main object record
      object_record = records.find { |r| r[:key]&.end_with?(':object') }
      unless object_record
        track_error({ email: email }, 'No :object record found in group')
        @stats[:customers_skipped] += 1
        return []
      end

      # Separate related records
      related_records = records.reject { |r| r[:key]&.end_with?(':object') }

      # Batch decode all hash records
      hash_records = records.select { |r| r[:type] == 'hash' }
      decoded_fields = {}

      @redis_helper.batch_restore_hashes(hash_records) do |record, fields|
        decoded_fields[record[:key]] = fields
      end

      # Resolve identifiers from the object record
      object_fields = decoded_fields[object_record[:key]] || {}
      objid, extid = resolve_identifiers(object_record, object_fields)

      unless objid && !objid.empty?
        @stats[:customers_skipped] += 1
        track_error({ key: object_record[:key] }, 'Could not resolve objid')
        return []
      end

      # Track email -> objid for downstream phases
      @email_to_objid[email] = objid

      # Transform all records
      v2_records = []

      # Transform the main object
      v2_object = transform_customer_object(object_record, object_fields, objid, extid)
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
      return [] unless key&.start_with?('customer:')

      warn "Warning: Customer record processed outside group: #{key}"
      []
    end

    def register_outputs
      @lookup_registry.register(:email_to_customer, @email_to_objid, phase: PHASE)
      @lookup_registry.save(:email_to_customer)

      puts "Registered #{@email_to_objid.size} email->customer mappings"
    end

    def print_custom_stats
      puts
      puts 'Transformation Stats:'
      puts "  Groups processed: #{@stats[:groups_processed]}"
      puts "  Transformed objects: #{@stats[:transformed_objects]}"
      puts "  Related records: #{@stats[:related_records]}"
      puts "  Customers skipped: #{@stats[:customers_skipped]}"
      puts
      puts 'Related Record Types:'
      puts "  Metadata->Receipts renamed: #{@stats[:renamed_metadata_to_receipts]}"
      puts "  Feature flags processed: #{@stats[:feature_flags_processed]}"
      puts "  Sorted sets processed: #{@stats[:sorted_sets_processed]}"
    end

    private

    def resolve_identifiers(record, fields)
      objid = record[:objid] || fields['objid']
      extid = record[:extid] || fields['extid']
      [objid, extid]
    end

    def transform_customer_object(v1_record, v1_fields, objid, extid)
      v2_fields = v1_fields.dup

      # Set canonical identifiers
      v2_fields['objid'] = objid
      v2_fields['extid'] = extid if extid && !extid.empty?

      # custid (email) -> custid (objid), preserving original
      if v2_fields['custid'] != objid
        v2_fields['v1_custid'] = v2_fields['custid']
      end
      v2_fields['custid'] = objid

      # Add migration tracking fields
      v2_fields['v1_identifier'] = v1_record[:key]
      v2_fields['migration_status'] = 'completed'
      v2_fields['migrated_at'] = Time.now.to_f.to_s

      v2_dump_b64 = create_dump(v2_fields)

      {
        key: "customer:#{objid}:object",
        type: 'hash',
        ttl_ms: v1_record[:ttl_ms],
        db: v1_record[:db],
        dump: v2_dump_b64,
        objid: objid,
        extid: v2_fields['extid'],
      }
    end

    def transform_related_record(record, objid, fields)
      key = record[:key]
      suffix = key.split(':').last

      case suffix
      when 'metadata'
        transform_metadata_to_receipts(record, objid, fields)
      when 'receipts'
        transform_sorted_set_record(record, objid, 'receipts')
      when 'feature_flags'
        transform_feature_flags(record, objid, fields)
      else
        transform_generic_related(record, objid, suffix)
      end
    end

    def transform_metadata_to_receipts(record, objid, fields)
      @stats[:renamed_metadata_to_receipts] += 1

      if record[:type] == 'zset'
        transform_sorted_set_record(record, objid, 'receipts')
      elsif fields
        v2_dump = create_dump(fields)
        {
          key: "customer:#{objid}:receipts",
          type: 'hash',
          ttl_ms: record[:ttl_ms],
          db: record[:db],
          dump: v2_dump,
        }
      end
    end

    def transform_sorted_set_record(record, objid, suffix)
      @stats[:sorted_sets_processed] += 1

      {
        key: "customer:#{objid}:#{suffix}",
        type: 'zset',
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: record[:dump],
      }
    end

    def transform_feature_flags(record, objid, fields)
      @stats[:feature_flags_processed] += 1

      return nil unless fields

      v2_dump = create_dump(fields)
      {
        key: "customer:#{objid}:feature_flags",
        type: 'hash',
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: v2_dump,
      }
    end

    def transform_generic_related(record, objid, suffix)
      warn "Warning: Unknown related record type: #{suffix} for customer #{objid}"

      {
        key: "customer:#{objid}:#{suffix}",
        type: record[:type],
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: record[:dump],
      }
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Migration::CustomerTransform.new.run(ARGV)
end
