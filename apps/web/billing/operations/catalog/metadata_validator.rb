# apps/web/billing/operations/catalog/metadata_validator.rb
#
# frozen_string_literal: true

require_relative '../../metadata'

module Billing
  module Operations
    module Catalog
      # Validates Stripe product metadata for plan extraction.
      #
      # Shared validation logic used by both DataExtractor (for fail-closed
      # extraction) and Plan (for diagnostic reporting).
      #
      module MetadataValidator
        class << self
          # Validate required metadata, raising on problems
          #
          # Checks both key presence AND non-blank values for required fields.
          #
          # @param product [Stripe::Product]
          # @raise [Onetime::ConfigError] If validation fails
          def validate!(product)
            result = validate(product)
            return if result[:valid]

            raise Onetime::ConfigError,
              "invalid metadata for Stripe product #{product.id} (#{product.name}): #{result[:problems].join('; ')}"
          end

          # Validate product metadata without raising
          #
          # Returns a hash with :valid, :missing, :blank, and :problems keys.
          #
          # @param product [Stripe::Product] The Stripe product
          # @return [Hash] { valid: Boolean, missing: [...], blank: [...], problems: [...] }
          def validate(product)
            required = Metadata::REQUIRED_FIELDS
            metadata = product.metadata || {}
            keys     = metadata.keys.map(&:to_s)
            missing  = required - keys

            # Check present keys for blank values
            blank = (required - missing).select do |key|
              metadata[key].to_s.strip.empty?
            end

            problems = []
            problems << "missing: #{missing.join(', ')}" if missing.any?
            problems << "blank: #{blank.join(', ')}" if blank.any?

            {
              valid: problems.empty?,
              missing: missing,
              blank: blank,
              problems: problems,
            }
          end
        end
      end
    end
  end
end
