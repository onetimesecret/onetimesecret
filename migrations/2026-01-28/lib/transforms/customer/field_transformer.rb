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
      # - Renames key from email-based to objid-based
      #
      # Usage in Kiba job:
      #   transform Customer::FieldTransformer, stats: stats
      #
      class FieldTransformer < BaseTransform
        attr_reader :migrated_at

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: job start time)
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
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

          # Preserve original custid (email) and update to objid
          original_custid = v1_fields['custid']
          if original_custid && original_custid != objid
            v2_fields['v1_custid'] = original_custid
          end
          v2_fields['custid'] = objid

          # Add migration tracking
          v2_fields['v1_identifier'] = record[:key]
          v2_fields['migration_status'] = 'completed'
          v2_fields['migrated_at'] = @migrated_at.to_f.to_s

          v2_fields
        end

        def build_v2_record(record, v2_fields, objid, extid)
          increment_stat(:objects_transformed)

          {
            key: "customer:#{objid}:object",
            type: 'hash',
            ttl_ms: record[:ttl_ms],
            db: record[:db],
            objid: objid,
            extid: extid,
            v2_fields: v2_fields,
          }
        end

        def rename_related_record(record)
          key_parts = record[:key].split(':')
          return record unless key_parts.size >= 3 && key_parts.first == 'customer'

          # Need the objid for this customer - check if it's in the record
          # For related records, we need to look up from customer context
          # In Kiba pipeline, this happens in a grouping stage or via context
          # For now, pass through - the job orchestrator handles customer grouping

          increment_stat(:related_passthrough)
          record
        end
      end
    end
  end
end
