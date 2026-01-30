#!/usr/bin/env ruby
# frozen_string_literal: true

# Phase 5: Secret Transformation
#
# Transforms V1 secret records to V2 format.
# This is the final phase - no downstream dependencies.
#
# V1 Key Patterns:
#   secret:{objid}:object  - Hash: main secret data
#
# V2 Key Patterns:
#   secret:{objid}:object  - Hash: main secret data (key pattern unchanged)
#
# Transformations:
#   - custid (email) -> owner_id (customer objid)
#   - State transforms: 'viewed' -> 'previewed', 'received' -> 'revealed'
#   - Field renames: viewed -> previewed, received -> revealed (keep originals)
#   - original_size -> v1_original_size (move and delete original)
#   - Migration tracking fields added
#
# CRITICAL: ciphertext, value, passphrase fields are preserved exactly as-is.
#           Do NOT re-encrypt or modify these fields in any way.
#
# Usage:
#   ruby transforms/05_secret_transform.rb [OPTIONS]
#
# Options:
#   --input-file=FILE   Input JSONL dump file (default: exports/secret/secret_dump.jsonl)
#   --output-dir=DIR    Output directory (default: exports/secret)
#   --dry-run           Parse and count without writing output
#   --help              Show help
#

require_relative '../lib/migration'

module Migration
  class SecretTransform < TransformerBase
    PHASE = 5
    MODEL_NAME = 'secret'

    # State value transforms
    STATE_TRANSFORMS = {
      'viewed' => 'previewed',
      'received' => 'revealed',
    }.freeze

    # Fields that must be preserved exactly (no modification)
    PRESERVED_FIELDS = %w[
      ciphertext value value_encryption passphrase passphrase_encryption
    ].freeze

    def initialize
      super
    end

    def default_stats
      super.merge(
        secrets_transformed: 0,
        secrets_skipped: 0,
        anonymous_secrets: 0,
        owner_lookups_failed: 0,
        state_transforms: Hash.new(0),
        original_size_moved: 0,
      )
    end

    def validate_prerequisites!
      # Phase 5 requires Phase 1 (Customer) for email->objid lookup
      @manifest.validate_dependencies!(PHASE)

      # Load required lookups
      @lookup_registry.require_lookup(:email_to_customer, for_phase: PHASE)

      # Also load customer_to_org for org_id linkage
      @lookup_registry.require_lookup(:customer_to_org, for_phase: PHASE)
    end

    # No grouping needed - each secret is independent
    def grouping_key_for(record)
      nil
    end

    # Process a single secret record
    def process_record(record)
      return [] if @options[:dry_run]

      key = record[:key]
      return [] unless key&.start_with?('secret:')
      return [] unless key&.end_with?(':object')

      # Decode the secret hash
      v1_fields = restore_hash(record)
      unless v1_fields
        track_error({ key: key }, 'Could not decode secret hash')
        @stats[:secrets_skipped] += 1
        return []
      end

      # Build V2 fields
      v2_fields = transform_secret(v1_fields, record)

      # Create V2 record
      v2_dump = create_dump(v2_fields)
      @stats[:secrets_transformed] += 1

      objid = v2_fields['objid']

      [{
        key: "secret:#{objid}:object",
        type: 'hash',
        ttl_ms: record[:ttl_ms],
        db: record[:db],
        dump: v2_dump,
        objid: objid,
      }]
    end

    def register_outputs
      # Phase 5 is terminal - no outputs to register
      puts 'Phase 5 is terminal - no lookups to register'
    end

    def print_custom_stats
      puts
      puts 'Secret Transformation Stats:'
      puts "  Secrets transformed: #{@stats[:secrets_transformed]}"
      puts "  Secrets skipped: #{@stats[:secrets_skipped]}"
      puts "  Anonymous secrets: #{@stats[:anonymous_secrets]}"
      puts "  Owner lookups failed: #{@stats[:owner_lookups_failed]}"
      puts "  Original size field moved: #{@stats[:original_size_moved]}"
      puts
      puts 'State Transforms:'
      @stats[:state_transforms].each do |from_to, count|
        puts "  #{from_to}: #{count}"
      end
    end

    private

    def transform_secret(v1_fields, source_record)
      v2_fields = v1_fields.dup

      # Resolve owner_id from custid
      custid = v1_fields['custid']
      if custid == 'anon' || custid.nil? || custid.empty?
        v2_fields['owner_id'] = 'anon'
        @stats[:anonymous_secrets] += 1
      else
        owner_id = resolve_owner_id(custid)
        if owner_id
          v2_fields['owner_id'] = owner_id
          # Also resolve org_id
          org_id = lookup(:customer_to_org, owner_id)
          v2_fields['org_id'] = org_id if org_id
        else
          v2_fields['owner_id'] = 'anon'
          @stats[:owner_lookups_failed] += 1
        end
      end

      # Preserve original custid
      v2_fields['v1_custid'] = custid if custid && custid != v2_fields['owner_id']

      # State transform
      if v1_fields['state']
        old_state = v1_fields['state']
        new_state = STATE_TRANSFORMS[old_state] || old_state
        if new_state != old_state
          v2_fields['state'] = new_state
          @stats[:state_transforms]["#{old_state}->#{new_state}"] += 1
        end
      end

      # Field renames (keep originals for backward compatibility)
      if v1_fields['viewed']
        v2_fields['previewed'] = v1_fields['viewed']
      end
      if v1_fields['received']
        v2_fields['revealed'] = v1_fields['received']
      end

      # Move original_size to v1_original_size
      if v1_fields['original_size']
        v2_fields['v1_original_size'] = v1_fields['original_size']
        v2_fields.delete('original_size')
        @stats[:original_size_moved] += 1
      end

      # Migration tracking
      v2_fields['v1_identifier'] = source_record[:key]
      v2_fields['v1_key'] = source_record[:key]
      v2_fields['migration_status'] = 'completed'
      v2_fields['migrated_at'] = Time.now.to_f.to_s
      v2_fields['_original_record'] = JSON.generate(v1_fields)

      v2_fields
    end

    def resolve_owner_id(custid)
      # custid is an email, look up the customer objid
      lookup(:email_to_customer, custid)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Migration::SecretTransform.new.run(ARGV)
end
