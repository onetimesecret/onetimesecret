# migrations/2026-01-28/lib/transforms/receipt/field_transformer.rb
#
# frozen_string_literal: true

require 'digest'

module Migration
  module Transforms
    module Receipt
      # Transforms metadata/receipt fields from V1 to V2 format.
      #
      # Applies the following transformations:
      # - Generates objid/extid from metadata key (deterministic)
      # - Resolves custid to owner_id via lookup
      # - Resolves customer email to org_id via lookup
      # - Resolves share_domain to domain_id via lookup (optional)
      # - Adds migration tracking fields
      # - Renames key from metadata: to receipt:
      #
      # Usage in Kiba job:
      #   transform Receipt::FieldTransformer,
      #             registry: lookup_registry,
      #             stats: stats,
      #             migrated_at: job_started_at
      #
      class FieldTransformer < BaseTransform
        requires_lookups :email_to_customer, :email_to_org, :fqdn_to_domain

        EXTID_PREFIX = 'rc'

        attr_reader :migrated_at

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: job start time)
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
          @uuid_generator = Shared::UuidV7Generator.new
        end

        # Process metadata record and transform fields.
        #
        # @param record [Hash] Record with :fields, :key
        # @return [Hash] Transformed record
        #
        def process(record)
          key = record[:key]

          # Only transform metadata :object records
          unless key&.end_with?(':object') && key&.start_with?('metadata:')
            increment_stat(:skipped_non_metadata_object)
            return nil
          end

          fields = record[:fields]
          unless fields
            increment_stat(:skipped_no_fields)
            return nil
          end

          # Extract the secret key from the metadata record
          secret_key = fields['key']
          unless secret_key && !secret_key.empty?
            increment_stat(:skipped_no_secret_key)
            return nil
          end

          # Generate deterministic identifiers from the secret key
          created = extract_created_timestamp(fields, record)
          objid = generate_receipt_objid(secret_key, created)
          extid = @uuid_generator.derive_extid(objid, prefix: EXTID_PREFIX)

          # Transform fields
          v2_fields = transform_fields(fields, objid, extid, record)

          # Build V2 record
          build_v2_record(record, v2_fields, objid, extid)
        end

        private

        def transform_fields(v1_fields, objid, extid, record)
          v2_fields = v1_fields.dup

          # Set canonical identifiers
          v2_fields['objid'] = objid
          v2_fields['extid'] = extid

          # Resolve ownership via lookups
          custid = v1_fields['custid']
          if custid && !custid.empty?
            v2_fields['v1_custid'] = custid

            # Lookup customer objid
            owner_id = lookup(:email_to_customer, custid)
            v2_fields['owner_id'] = owner_id if owner_id
            increment_stat(:owner_resolved) if owner_id
            increment_stat(:owner_unresolved) unless owner_id

            # Lookup organization objid
            org_id = lookup(:email_to_org, custid)
            v2_fields['org_id'] = org_id if org_id
            increment_stat(:org_resolved) if org_id
            increment_stat(:org_unresolved) unless org_id
          else
            increment_stat(:no_custid)
          end

          # Resolve custom domain if present
          share_domain = v1_fields['share_domain']
          if share_domain && !share_domain.empty?
            domain_id = lookup(:fqdn_to_domain, share_domain)
            v2_fields['domain_id'] = domain_id if domain_id
            increment_stat(:domain_resolved) if domain_id
            increment_stat(:domain_unresolved) unless domain_id
          end

          # Add migration tracking
          v2_fields['v1_identifier'] = record[:key]
          v2_fields['migration_status'] = 'completed'
          v2_fields['migrated_at'] = @migrated_at.to_f.to_s

          v2_fields
        end

        def build_v2_record(record, v2_fields, objid, extid)
          increment_stat(:objects_transformed)

          # Receipt key uses the secret key directly (same as metadata)
          # Only the prefix changes: metadata:KEY:object -> receipt:KEY:object
          secret_key = v2_fields['key']

          {
            key: "receipt:#{secret_key}:object",
            type: 'hash',
            ttl_ms: record[:ttl_ms],
            db: record[:db],
            objid: objid,
            extid: extid,
            secret_key: secret_key,
            v2_fields: v2_fields,
          }
        end

        def extract_created_timestamp(fields, record)
          # Try record-level first, then fields
          ts = record[:created] || fields['created']
          ts ? ts.to_f.to_i : Time.now.to_i
        end

        # Generate deterministic receipt objid from secret key and timestamp.
        #
        # Uses UUIDv7 format with:
        # - Timestamp from receipt's created date (preserves chronological ordering)
        # - Deterministic "random" bits derived from secret key (reproducible)
        #
        def generate_receipt_objid(secret_key, created_timestamp)
          # Create deterministic seed from secret key
          seed = Digest::SHA256.digest("receipt:#{secret_key}")

          # Use receipt's created timestamp for UUIDv7 time component
          timestamp_ms = (created_timestamp.to_f * 1000).to_i

          # Encode timestamp as 48-bit hex (12 hex chars)
          hex = timestamp_ms.to_s(16).rjust(12, '0')

          # Use deterministic PRNG seeded from secret key
          prng = Random.new(seed.unpack1('Q>'))
          rand_bytes = prng.bytes(10)
          rand_hex = rand_bytes.unpack1('H*')

          # Construct UUID v7 parts
          time_hi = hex[0, 8]
          time_mid = hex[8, 4]
          ver_rand = '7' + rand_hex[0, 3]
          variant = ((rand_hex[4, 2].to_i(16) & 0x3F) | 0x80).to_s(16).rjust(2, '0') + rand_hex[6, 2]
          node = rand_hex[8, 12]

          "#{time_hi}-#{time_mid}-#{ver_rand}-#{variant}-#{node}"
        end
      end
    end
  end
end
