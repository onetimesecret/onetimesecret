# frozen_string_literal: true

module Migration
  module Transforms
    module Customer
      # Enriches customer records with UUIDv7 objid and derived extid.
      #
      # Only processes :object records that have a 'created' timestamp.
      # Uses the timestamp to generate deterministic-ish UUIDv7 identifiers.
      #
      # Also builds an email_to_objid mapping that can be shared with
      # FieldTransformer for renaming related records.
      #
      # Usage in Kiba job:
      #   email_mapping = {}
      #   transform Customer::IdentifierEnricher, email_mapping: email_mapping
      #   transform Customer::FieldTransformer, email_mapping: email_mapping
      #
      class IdentifierEnricher < BaseTransform
        EXTID_PREFIX = 'ur'

        attr_reader :email_mapping

        # @param email_mapping [Hash] Shared hash with pre-built email→objid mappings.
        #        If provided and contains the email, uses existing objid instead of generating new one.
        # @param kwargs [Hash] Additional options passed to BaseTransform
        #
        def initialize(email_mapping: nil, **kwargs)
          super(**kwargs)
          @uuid_generator = Migration::Shared::UuidV7Generator.new
          @email_mapping = email_mapping || {}
        end

        # Add objid and extid to record if it's an enrichable :object record.
        #
        # @param record [Hash] Input record
        # @return [Hash] Record with objid/extid added (if applicable)
        #
        def process(record)
          # Skip if already has identifiers (from enriched dump)
          if record[:objid] && !record[:objid].empty?
            increment_stat(:already_enriched)
            return record
          end

          # Only enrich :object records
          key = record[:key]
          unless key&.end_with?(':object')
            increment_stat(:skipped_non_object)
            return record
          end

          # Extract email to check pre-built mapping
          email = extract_email(record)

          # Use pre-built objid if available (ensures consistency with related records)
          if email && @email_mapping[email]
            objid = @email_mapping[email]
            extid = @uuid_generator.derive_extid(objid, prefix: EXTID_PREFIX)

            record[:objid] = objid
            record[:extid] = extid
            increment_stat(:enriched_from_mapping)

            return record
          end

          # Need 'created' timestamp from either record or fields
          created = extract_created_timestamp(record)
          unless created && created > 0
            increment_stat(:skipped_no_timestamp)
            return record
          end

          # Generate identifiers
          objid, extid = @uuid_generator.generate_identifiers(created, prefix: EXTID_PREFIX)

          record[:objid] = objid
          record[:extid] = extid

          # Store email→objid mapping for related record renaming
          @email_mapping[email] = objid if email && !email.empty?

          increment_stat(:enriched)

          record
        end

        def extract_email(record)
          fields = record[:fields]
          return nil unless fields

          fields['custid'] || fields['email']
        end

        private

        def extract_created_timestamp(record)
          # Check record-level first (from prior enrichment)
          return record[:created].to_f if record[:created]

          # Check decoded fields
          fields = record[:fields]
          return fields['created'].to_f if fields && fields['created']

          nil
        end
      end
    end
  end
end
