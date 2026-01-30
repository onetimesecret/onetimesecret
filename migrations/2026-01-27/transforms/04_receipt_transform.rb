#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 4: Receipt Transformation
#
# Transforms V1 metadata records to V2 receipt format.
# Renames the model from "metadata" to "receipt" for clarity.
#
# V1 Key Patterns:
#   metadata:{objid}:object  - Hash: receipt/metadata data
#
# V2 Key Patterns:
#   receipt:{objid}:object   - Hash: receipt data
#
# Transformations:
#   - Key prefix: metadata -> receipt
#   - custid (email) -> owner_id (customer objid)
#   - custid (email) -> org_id (via customer->org lookup)
#   - share_domain -> domain_id (via fqdn_to_domain lookup)
#   - state: 'viewed' -> 'previewed'
#   - state: 'received' -> 'revealed'
#   - viewed -> previewed (field rename, keep original)
#   - received -> revealed (field rename, keep original)
#   - Migration tracking fields added
#
# Output Lookup:
#   None (terminal phase for lookups)
#
# Usage:
#   ruby transforms/04_receipt_transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: results/metadata_dump.jsonl)
#   --output-dir=DIR    Output directory (default: results)
#   --dry-run           Parse and count without writing output
#   --help              Show help
#

require_relative '../lib/migration'

module Migration
  class ReceiptTransform < TransformerBase
    PHASE = 4
    MODEL_NAME = 'receipt'

    # State value transformations
    STATE_TRANSFORMS = {
      'viewed' => 'previewed',
      'received' => 'revealed',
    }.freeze

    def initialize
      super
      @email_to_customer = nil
      @customer_to_org = nil
      @fqdn_to_domain = nil
    end

    def default_stats
      super.merge(
        receipts_transformed: 0,
        receipts_skipped: 0,
        anonymous_receipts: 0,
        owner_lookup_failures: 0,
        org_lookup_failures: 0,
        domain_lookup_failures: 0,
        state_transforms: Hash.new(0),
        with_share_domain: 0,
        with_org_link: 0,
      )
    end

    def setup_defaults
      # Override to use metadata dump as input (V1 naming)
      results_dir = @options[:results_dir]
      @options[:input_file] ||= File.join(results_dir, 'metadata_dump.jsonl')
      @options[:output_dir] ||= results_dir
    end

    def validate_prerequisites!
      # Phase 4 requires Phases 1, 2, and 3 to be complete
      @manifest.validate_dependencies!(PHASE)

      # Load required lookups from earlier phases
      @email_to_customer = @lookup_registry.require_lookup(:email_to_customer, for_phase: PHASE)
      @customer_to_org = @lookup_registry.require_lookup(:customer_to_org, for_phase: PHASE)
      @fqdn_to_domain = @lookup_registry.require_lookup(:fqdn_to_domain, for_phase: PHASE)
    end

    # No grouping needed - each metadata record is independent
    def grouping_key_for(record)
      nil
    end

    # Process a single metadata record
    def process_record(record)
      return [] if @options[:dry_run]

      key = record[:key]
      return [] unless key&.end_with?(':object')
      return [] unless key&.start_with?('metadata:')

      # Decode the metadata hash to get fields
      fields = restore_hash(record)
      unless fields
        track_error({ key: key }, 'Could not decode metadata hash')
        @stats[:receipts_skipped] += 1
        return []
      end

      objid = record[:objid] || fields['objid']
      unless objid && !objid.empty?
        track_error({ key: key }, 'Receipt missing objid')
        @stats[:receipts_skipped] += 1
        return []
      end

      # Transform the record
      v2_fields = transform_receipt_fields(fields, record)

      # Create the V2 receipt record
      v2_dump = create_dump(v2_fields)
      @stats[:receipts_transformed] += 1

      [{
        key: "receipt:#{objid}:object",
        type: 'hash',
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: v2_dump,
        objid: objid,
        extid: v2_fields['extid'],
      }]
    end

    def register_outputs
      # Phase 4 does not produce lookups for downstream phases
      puts 'No lookups to register (terminal phase)'
    end

    def print_custom_stats
      puts
      puts 'Receipt Transformation Stats:'
      puts "  Receipts transformed: #{@stats[:receipts_transformed]}"
      puts "  Receipts skipped: #{@stats[:receipts_skipped]}"
      puts "  Anonymous receipts: #{@stats[:anonymous_receipts]}"
      puts
      puts 'Linkage Stats:'
      puts "  With org link: #{@stats[:with_org_link]}"
      puts "  With share domain: #{@stats[:with_share_domain]}"
      puts
      puts 'Lookup Failures:'
      puts "  Owner lookup failures: #{@stats[:owner_lookup_failures]}"
      puts "  Org lookup failures: #{@stats[:org_lookup_failures]}"
      puts "  Domain lookup failures: #{@stats[:domain_lookup_failures]}"
      puts
      puts 'State Transforms:'
      @stats[:state_transforms].each do |from_state, count|
        to_state = STATE_TRANSFORMS[from_state] || from_state
        puts "  #{from_state} -> #{to_state}: #{count}"
      end
    end

    private

    def transform_receipt_fields(v1_fields, source_record)
      v2_fields = v1_fields.dup
      custid = v1_fields['custid']

      # Preserve original custid
      v2_fields['v1_custid'] = custid if custid

      # Resolve owner_id from custid
      if custid == 'anon'
        v2_fields['owner_id'] = 'anon'
        @stats[:anonymous_receipts] += 1
      else
        owner_id = resolve_owner_id(custid)
        if owner_id
          v2_fields['owner_id'] = owner_id

          # Resolve org_id from owner_id
          org_id = resolve_org_id(owner_id)
          if org_id
            v2_fields['org_id'] = org_id
            @stats[:with_org_link] += 1
          else
            @stats[:org_lookup_failures] += 1
          end
        else
          @stats[:owner_lookup_failures] += 1
          v2_fields['owner_id'] = 'anon' # Fallback
        end
      end

      # Remove custid (replaced by owner_id)
      v2_fields.delete('custid')

      # Resolve domain_id from share_domain
      share_domain = v1_fields['share_domain']
      if share_domain && !share_domain.empty?
        domain_id = resolve_domain_id(share_domain)
        if domain_id
          v2_fields['domain_id'] = domain_id
          @stats[:with_share_domain] += 1
        else
          @stats[:domain_lookup_failures] += 1
        end
      end

      # Transform state values
      state = v1_fields['state']
      if state && STATE_TRANSFORMS.key?(state)
        v2_fields['state'] = STATE_TRANSFORMS[state]
        @stats[:state_transforms][state] += 1
      end

      # Field renames (keep originals for backward compatibility)
      if v1_fields['viewed']
        v2_fields['previewed'] = v1_fields['viewed']
      end
      if v1_fields['received']
        v2_fields['revealed'] = v1_fields['received']
      end

      # Add migration tracking fields
      v2_fields['v1_identifier'] = source_record[:key]
      v2_fields['v1_key'] = source_record[:key]
      v2_fields['migration_status'] = 'completed'
      v2_fields['migrated_at'] = Time.now.to_f.to_s
      v2_fields['_original_record'] = JSON.generate(v1_fields)

      v2_fields
    end

    def resolve_owner_id(custid)
      return nil unless custid
      @email_to_customer[custid]
    end

    def resolve_org_id(owner_id)
      return nil unless owner_id
      @customer_to_org[owner_id]
    end

    def resolve_domain_id(share_domain)
      return nil unless share_domain
      @fqdn_to_domain[share_domain]
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Migration::ReceiptTransform.new.run(ARGV)
end
