# migrations/2026-01-28/lib/transforms/secret/field_transformer.rb
#
# frozen_string_literal: true

module Migration
  module Transforms
    module Secret
      # Transforms secret object fields from V1 to V2 format.
      #
      # CRITICAL: The encrypted value field MUST be preserved EXACTLY as-is.
      # Any modification to the value would corrupt the encrypted content.
      #
      # Applies the following transformations:
      # - Generates objid from created timestamp
      # - Derives extid with 'se' prefix
      # - Looks up owner_id from email_to_customer (nil for anonymous)
      # - Looks up org_id from email_to_org (nil for anonymous)
      # - Preserves value and value_checksum EXACTLY
      # - Adds migration tracking fields
      # - Renames key from v1 format to objid-based
      #
      # Usage in Kiba job:
      #   transform Secret::FieldTransformer, stats: stats, registry: registry
      #
      class FieldTransformer < BaseTransform
        # NOTE: fqdn_to_domain resolves share_domain FQDN to domain_id
        requires_lookups :email_to_customer, :email_to_org, :fqdn_to_domain

        attr_reader :migrated_at, :uuid_generator

        # @param migrated_at [Time, nil] Timestamp for migration tracking (default: job start time)
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(migrated_at: nil, **kwargs)
          super(**kwargs)
          @migrated_at = migrated_at || Time.now
          @uuid_generator = Shared::UuidV7Generator.new
        end

        # Process secret record and transform fields.
        #
        # @param record [Hash] Record with :fields
        # @return [Hash] Transformed record
        #
        def process(record)
          key = record[:key]

          # Only process secret: keys
          unless key&.start_with?('secret:')
            increment_stat(:skipped_non_secret)
            return record
          end

          # Only transform :object records
          unless key&.end_with?(':object')
            # For related records (metadata, etc.), just pass through
            increment_stat(:related_passthrough)
            return record
          end

          fields = record[:fields]
          unless fields
            increment_stat(:skipped_no_fields)
            return record
          end

          # Transform fields
          v2_fields = transform_fields(fields, record)

          # Build V2 record
          build_v2_record(record, v2_fields)
        end

        private

        def transform_fields(v1_fields, record)
          v2_fields = v1_fields.dup

          # Generate identifiers from created timestamp
          created_ts = v1_fields['created']&.to_f || Time.now.to_f
          objid, extid = @uuid_generator.generate_identifiers(created_ts, prefix: 'se')

          v2_fields['objid'] = objid
          v2_fields['extid'] = extid

          # Lookup owner and org from custid (email)
          custid = v1_fields['custid']
          if custid && custid != 'anon' && !custid.empty?
            owner_id = lookup(:email_to_customer, custid, strict: false)
            org_id = lookup(:email_to_org, custid, strict: false)

            v2_fields['owner_id'] = owner_id if owner_id
            v2_fields['org_id'] = org_id if org_id

            increment_stat(:anonymous_secrets) unless owner_id
          else
            increment_stat(:anonymous_secrets)
          end

          # CRITICAL: value and value_checksum are preserved exactly as-is
          # They are already in v2_fields from the dup above

          # Lookup domain_id from share_domain (FQDN)
          share_domain = v1_fields['share_domain']
          if share_domain && !share_domain.empty?
            domain_id = lookup(:fqdn_to_domain, share_domain, strict: false)
            v2_fields['domain_id'] = domain_id if domain_id
            increment_stat(:domain_resolved) if domain_id
            increment_stat(:domain_unresolved) unless domain_id
          end

          # Add migration tracking
          v2_fields['v1_identifier'] = record[:key]
          v2_fields['migration_status'] = 'completed'
          v2_fields['migrated_at'] = @migrated_at.to_f  # Float, not string

          v2_fields
        end

        def build_v2_record(record, v2_fields)
          increment_stat(:secrets_transformed)

          objid = v2_fields['objid']
          extid = v2_fields['extid']

          # Extract original secret key (the middle part of secret:<key>:object)
          # Secret key is preserved as-is - no lookup needed
          original_key = record[:key]
          secret_key = original_key.sub(/^secret:/, '').sub(/:object$/, '')

          {
            key: original_key,  # Keep original key: secret:<key>:object
            type: 'hash',
            ttl_ms: record[:ttl_ms],
            db: record[:db],
            objid: objid,
            extid: extid,
            secret_key: secret_key,
            v2_fields: v2_fields,
          }
        end
      end
    end
  end
end
