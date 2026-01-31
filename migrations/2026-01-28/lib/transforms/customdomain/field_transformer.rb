# migrations/2026-01-28/lib/transforms/customdomain/field_transformer.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Customdomain
      # Transforms customdomain object fields from V1 to V2 format.
      #
      # Applies the following transformations:
      # - Generates objid/extid with 'cd' prefix
      # - Looks up owner_id (customer objid) from custid (email)
      # - Looks up org_id (organization objid) from custid (email)
      # - Preserves original custid as v1_custid
      # - Adds migration tracking fields
      # - Renames key from display_domain-based to objid-based
      #
      # Usage in Kiba job:
      #   transform Customdomain::FieldTransformer,
      #             registry: registry,
      #             stats: stats,
      #             migrated_at: job_started_at
      #
      class FieldTransformer < BaseTransform
        EXTID_PREFIX = 'cd'

        requires_lookups :email_to_customer, :email_to_org

        attr_reader :migrated_at

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: job start time)
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
          @uuid_generator = Shared::UuidV7Generator.new
        end

        # Process customdomain record and transform fields.
        #
        # @param record [Hash] Record with :fields, :key
        # @return [Hash, nil] Transformed record, or nil if skipped
        #
        def process(record)
          key = record[:key]

          # Only transform :object records
          unless key&.end_with?(':object')
            increment_stat(:skipped_non_object)
            return nil
          end

          fields = record[:fields]
          unless fields
            increment_stat(:skipped_no_fields)
            return nil
          end

          # Extract custid (email) for lookups
          custid = fields['custid']
          unless custid && !custid.empty?
            increment_stat(:skipped_no_custid)
            return nil
          end

          # Look up owner_id and org_id
          owner_id = lookup(:email_to_customer, custid)
          org_id = lookup(:email_to_org, custid)

          unless owner_id
            increment_stat(:skipped_no_owner)
            record[:transform_error] = "Customer not found for custid: #{custid}"
            return nil
          end

          unless org_id
            increment_stat(:skipped_no_org)
            record[:transform_error] = "Organization not found for custid: #{custid}"
            return nil
          end

          # Generate identifiers for the domain
          created = extract_created_timestamp(fields, record)
          objid, extid = @uuid_generator.generate_identifiers(created, prefix: EXTID_PREFIX)

          # Transform fields
          v2_fields = transform_fields(fields, objid, extid, owner_id, org_id, record)

          # Build V2 record
          build_v2_record(record, v2_fields, objid, extid, owner_id, org_id)
        end

        private

        def transform_fields(v1_fields, objid, extid, owner_id, org_id, record)
          v2_fields = v1_fields.dup

          # Set canonical identifiers
          v2_fields['objid'] = objid
          v2_fields['extid'] = extid

          # Set owner and org references
          v2_fields['owner_id'] = owner_id
          v2_fields['org_id'] = org_id

          # Preserve original custid (email) and remove from fields
          original_custid = v1_fields['custid']
          v2_fields['v1_custid'] = original_custid
          v2_fields.delete('custid')

          # Add migration tracking
          v2_fields['v1_identifier'] = record[:key]
          v2_fields['migration_status'] = 'completed'
          v2_fields['migrated_at'] = @migrated_at.to_f  # Float, not string

          v2_fields
        end

        def build_v2_record(record, v2_fields, objid, extid, owner_id, org_id)
          increment_stat(:objects_transformed)

          # Extract display_domain for lookup output
          display_domain = v2_fields['display_domain']

          {
            key: "customdomain:#{objid}:object",
            type: 'hash',
            ttl_ms: record[:ttl_ms],
            db: record[:db],
            objid: objid,
            extid: extid,
            owner_id: owner_id,
            org_id: org_id,
            display_domain: display_domain,
            v2_fields: v2_fields,
          }
        end

        def extract_created_timestamp(fields, record)
          # Try record-level first, then fields
          ts = record[:created] || fields['created']
          ts ? ts.to_f.to_i : Time.now.to_i
        end
      end
    end
  end
end
