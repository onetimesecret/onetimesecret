# lib/onetime/field_types/float_field_type.rb
#
# frozen_string_literal: true

require_relative 'coercing_field_type'

module Onetime
  module FieldTypes
    # Coerces numeric inputs to native Float values for Familia scalar fields.
    class FloatFieldType < CoercingFieldType
      NUMERIC_STRING = /\A\s*-?\d+(?:\.\d+)?\s*\z/

      def initialize(name, storage: :native, **)
        validate_storage!(name, storage)
        super(name, **)
      end

      def coerce(value)
        return nil if value.nil? || value == ''
        return value if value.is_a?(Float)
        return value.to_f if !value.is_a?(String) && value.respond_to?(:to_f)
        return value.to_i.to_f if !value.is_a?(String) && value.respond_to?(:to_i)
        return Float(value) if value.is_a?(String) && NUMERIC_STRING.match?(value)

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
