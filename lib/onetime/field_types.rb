# lib/onetime/field_types.rb
#
# frozen_string_literal: true

# Load every concrete coercing type before extending FieldTypes::Macros.
require_relative 'field_types/boolean_field_type'
require_relative 'field_types/integer_field_type'
require_relative 'field_types/float_field_type'
