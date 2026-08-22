# lib/onetime/models/field_types/float_field_type.rb
#
# frozen_string_literal: true

require_relative 'coercing_field_type'

module Onetime
  module Models
    module FieldTypes
      # Coerces numeric inputs to native Float values for Familia scalar fields.
      class FloatFieldType < CoercingFieldType
        NUMERIC_STRING = /\A\s*-?\d+(?:\.\d+)?\s*\z/

        def initialize(name, storage: :native, **)
          validate_storage!(name, storage)
          super(name, **)
        end

        # Non-finite results (NaN, the infinities) are invalid: JSON
        # persistence rejects them, so retaining one makes the row unsavable.
        # Conversion errors from numeric-ish inputs (e.g. BigDecimal NaN)
        # follow the same invalid-value contract instead of raising.
        def coerce(value)
          return nil if value.nil? || value == ''

          result =
            if value.is_a?(Float)
              value
            elsif value.is_a?(String)
              Float(value) if NUMERIC_STRING.match?(value)
            elsif value.respond_to?(:to_f)
              value.to_f
            elsif value.respond_to?(:to_i)
              value.to_i.to_f
            end

          return result if result.is_a?(Float) && result.finite?

          log_coercion_issue(value)
          nil
        rescue RangeError, TypeError, ArgumentError
          log_coercion_issue(value)
          nil
        end

        private

        def validate_storage!(name, storage)
          return if storage == :native

          raise ArgumentError, "Unknown float storage #{storage.inspect} for field #{name} (expected :native)"
        end
      end
    end
  end
end
