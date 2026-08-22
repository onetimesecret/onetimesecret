# lib/onetime/models/field_types/integer_field_type.rb
#
# frozen_string_literal: true

require_relative 'coercing_field_type'

module Onetime
  module Models
    module FieldTypes
      # Coerces numeric inputs to native Integer values for Familia scalar fields.
      class IntegerFieldType < CoercingFieldType
        NUMERIC_STRING = /\A\s*-?\d+(?:\.\d+)?\s*\z/

        def initialize(name, storage: :native, **)
          validate_storage!(name, storage)
          super(name, **)
        end

        # Non-finite floats raise FloatDomainError (a RangeError) from #to_i;
        # they and any other conversion failure follow the invalid-value
        # contract (warn, coerce to nil) instead of raising through the setter.
        def coerce(value)
          return nil if value.nil? || value == ''

          result =
            if value.is_a?(Integer)
              value
            elsif value.is_a?(String)
              value.to_i if NUMERIC_STRING.match?(value)
            elsif value.respond_to?(:to_i)
              value.to_i
            end

          return result if result.is_a?(Integer)

          log_coercion_issue(value)
          nil
        rescue RangeError, TypeError, ArgumentError
          log_coercion_issue(value)
          nil
        end

        private

        def validate_storage!(name, storage)
          return if storage == :native

          raise ArgumentError, "Unknown integer storage #{storage.inspect} for field #{name} (expected :native)"
        end
      end
    end
  end
end
