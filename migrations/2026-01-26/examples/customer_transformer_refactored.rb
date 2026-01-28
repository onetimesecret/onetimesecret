#!/usr/bin/env ruby
# frozen_string_literal: true

# EXAMPLE: Refactored Customer Transformer using Migration::TransformerBase
#
# This demonstrates how to migrate the existing transform scripts to use
# the shared infrastructure in lib/. Compare with 01-customer/transform.rb.
#
# Key differences:
# - Inherits from TransformerBase (reduces ~150 lines of boilerplate)
# - Uses RedisHelper for restore/dump operations
# - Uses LookupRegistry for managing output mappings
# - Automatic stats tracking and error handling
# - Automatic manifest updates
#
# Usage:
#   ruby examples/customer_transformer_refactored.rb [OPTIONS]
#

require_relative '../lib/migration'

class CustomerTransformerRefactored < Migration::TransformerBase
  PHASE = 1
  MODEL_NAME = 'customer'

  # ExtID prefix for Customer model
  EXTID_PREFIX = 'ur'

  def initialize
    super
    @email_to_objid = {}  # Will be registered as output lookup
  end

  def default_stats
    super.merge(
      transformed_objects: 0,
      renamed_related: Hash.new(0),
      customers_skipped: 0,
    )
  end

  def validate_prerequisites!
    # Phase 1 has no prerequisites - it's the first phase
    # Just validate the manifest allows us to run
    @manifest.validate_dependencies!(PHASE)
  end

  def process_record(record)
    key = record[:key]
    return [] unless key

    # Group records by customer for processing
    # Note: In the full implementation, you'd batch these
    # For simplicity, this example processes individual :object records
    return [] unless key.end_with?(':object')
    return [] unless key.start_with?('customer:')

    return [] if @options[:dry_run]

    v1_fields = restore_hash(record)
    objid, extid = resolve_identifiers(record, v1_fields)

    unless objid && !objid.empty?
      @stats[:customers_skipped] += 1
      track_error({ key: key }, 'Could not resolve objid')
      return []
    end

    # Track email -> objid for downstream phases
    v1_custid = key.split(':')[1]
    @email_to_objid[v1_custid] = objid

    # Transform the customer object
    v2_record = transform_customer_object(record, v1_fields, objid, extid)
    @stats[:transformed_objects] += 1

    [v2_record]
  end

  def register_outputs
    # Save lookup for downstream phases (Organization, CustomDomain, etc.)
    @lookup_registry.register(:email_to_customer, @email_to_objid, phase: PHASE)
    @lookup_registry.save(:email_to_customer)

    puts "Registered #{@email_to_objid.size} email->customer mappings"
  end

  def print_custom_stats
    puts
    puts 'Transformation Stats:'
    puts "  Transformed objects: #{@stats[:transformed_objects]}"
    puts "  Customers skipped: #{@stats[:customers_skipped]}"
    puts
    puts 'Renamed Related Records:'
    @stats[:renamed_related].each do |type, count|
      puts "  #{type}: #{count}"
    end
    puts '  (none)' if @stats[:renamed_related].empty?
  end

  private

  def resolve_identifiers(record, fields)
    # Prefer enriched identifiers from JSONL record
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

    # Create new dump for the transformed hash
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
end

# Run if executed directly
if __FILE__ == $PROGRAM_NAME
  CustomerTransformerRefactored.new.run(ARGV)
end
