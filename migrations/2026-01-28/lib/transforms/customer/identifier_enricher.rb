# frozen_string_literal: true

module Migration
  module Transforms
    module Customer
      # Enriches customer records with UUIDv7 objid and derived extid.
      #
      # Only processes :object records that have a 'created' timestamp.
      # Uses the timestamp to generate deterministic-ish UUIDv7 identifiers.
      #
      # Usage in Kiba job:
      #   transform Customer::IdentifierEnricher
      #
      class IdentifierEnricher < BaseTransform
        EXTID_PREFIX = 'ur'

        def initialize(**kwargs)
          super(**kwargs)
          @uuid_generator = Migration::Shared::UuidV7Generator.new
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
          increment_stat(:enriched)

          record
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
