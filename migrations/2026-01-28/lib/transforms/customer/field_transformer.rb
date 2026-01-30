# frozen_string_literal: true

module Migration
  module Transforms
    module Customer
      # Transforms customer object fields from V1 to V2 format.
      #
      # Applies the following transformations:
      # - Sets objid/extid in hash fields
      # - Preserves original custid as v1_custid
      # - Updates custid to objid
      # - Adds migration tracking fields
      # - Renames key from email-based to objid-based (both :object and related records)
      #
      # Usage in Kiba job:
      #   transform Customer::FieldTransformer, stats: stats
      #
      class FieldTransformer < BaseTransform
        attr_reader :migrated_at, :email_mapping

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: job start time)
        # @param email_mapping [Hash] Shared email→objid mapping from IdentifierEnricher
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, email_mapping: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
          # Use shared mapping from IdentifierEnricher, or create local one
          # This allows renaming related records regardless of dump order
          @email_mapping = email_mapping || {}
        end

        # Process customer record and transform fields.
        #
        # @param record [Hash] Record with :fields, :objid, :extid
        # @return [Hash] Transformed record
        #
        def process(record)
          key = record[:key]

          # Only transform :object records
          unless key&.end_with?(':object')
            # For related records (metadata, secrets, etc.), just rename key
            return rename_related_record(record) if key&.include?(':')
            return record
          end

          fields = record[:fields]
          unless fields
            increment_stat(:skipped_no_fields)
            return record
          end

          objid = record[:objid]
          extid = record[:extid]

          unless objid && !objid.empty?
            increment_stat(:skipped_no_objid)
            return record
          end

          # Transform fields
          v2_fields = transform_fields(fields, objid, extid, record)

          # Build V2 record; lookup collection is handled by LookupDestination
          build_v2_record(record, v2_fields, objid, extid)
        end

        private

        def transform_fields(v1_fields, objid, extid, record)
          v2_fields = v1_fields.dup

          # Set canonical identifiers
          v2_fields['objid'] = objid
          v2_fields['extid'] = extid if extid && !extid.empty?

          # Preserve original custid (email) for lookup and update to objid
          # Use email as fallback when custid is missing to ensure lookup coverage
          # This ensures lookup file has entries for all customers
          original_custid = v1_fields['custid']
          original_custid = v1_fields['email'] if original_custid.nil? || original_custid.empty?
          v2_fields['v1_custid'] = original_custid if original_custid && !original_custid.empty?
          v2_fields['custid'] = objid

          # Add migration tracking
          v2_fields['v1_identifier'] = record[:key]
          v2_fields['migration_status'] = 'completed'
          v2_fields['migrated_at'] = @migrated_at.to_f.to_s

          v2_fields
        end

        def build_v2_record(record, v2_fields, objid, extid)
          increment_stat(:objects_transformed)

          # Also store in local mapping (for records processed after their :object)
          v1_custid = v2_fields['v1_custid']
          @email_mapping[v1_custid] = objid if v1_custid && !v1_custid.empty?

          {
            key: "customer:#{objid}:object",
            type: 'hash',
            ttl_ms: record[:ttl_ms],
            db: record[:db],
            objid: objid,
            extid: extid,
            v1_custid: v1_custid,
            v2_fields: v2_fields,
          }
        end

        # Suffix renames for V1 → V2 migration
        SUFFIX_RENAMES = {
          'metadata' => 'receipts',
        }.freeze

        def rename_related_record(record)
          key = record[:key]
          key_parts = key.split(':')
          return record unless key_parts.size >= 3 && key_parts.first == 'customer'

          # Extract email (middle part) and suffix
          # Format: customer:<email>:<suffix> e.g. customer:user@example.com:metadata
          email = key_parts[1]
          suffix = key_parts[2..-1].join(':')

          # Look up objid from shared mapping (populated by IdentifierEnricher)
          objid = @email_mapping[email]

          unless objid
            increment_stat(:related_no_objid)
            return record
          end

          increment_stat(:related_renamed)

          # Rename suffix if needed (e.g., metadata → receipts)
          new_suffix = SUFFIX_RENAMES[suffix] || suffix

          # Return record with renamed key
          record.merge(
            key: "customer:#{objid}:#{new_suffix}",
            v1_key: key
          )
        end
      end
    end
  end
end
