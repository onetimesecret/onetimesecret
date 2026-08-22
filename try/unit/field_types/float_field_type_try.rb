# try/unit/field_types/float_field_type_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require 'onetime/field_types/float_field_type'

OT.boot! :test, false

class FloatFieldTypeTryToIValue
  def initialize(value)
    @value = value
  end

  def to_i
    @value
  end
end

class FloatFieldTypeTryModel < ::Familia::Horreum
  extend Onetime::FieldTypes::Macros

  prefix :try_float_field_type
  identifier_field :probeid
  field :probeid
  float_field :value
end

FLOAT_FIELD_TYPE_EPOCH = 1_772_940_425

FLOAT_FIELD_TYPE_COERCION_CASES = [
  [nil, nil],
  ['', nil],
  [17, 17.0],
  [17.9, 17.9],
  [Time.at(FLOAT_FIELD_TYPE_EPOCH), FLOAT_FIELD_TYPE_EPOCH.to_f],
  [FloatFieldTypeTryToIValue.new(41), 41.0],
  ['  -17  ', -17.0],
  ['  17.9  ', 17.9],
  ['+17', nil],
  ['17.', nil],
  ['.17', nil],
  ['1e3', nil],
  ['- 17', nil],
  ['garbage', nil],
  [Object.new, nil],
].freeze

@float_field_type_try_records = []

def float_field_type_try_record
  record = FloatFieldTypeTryModel.new(probeid: "float-#{SecureRandom.hex(8)}")
  @float_field_type_try_records << record
  record
end

def float_field_type_try_coerce(value)
  record = float_field_type_try_record
  record.value = value
  record.value
end

def float_field_type_try_raw_value(record)
  record.dbclient.hmget(record.dbkey, 'value').first
end

def float_field_type_try_legacy_value(raw)
  record = float_field_type_try_record
  record.save
  record.dbclient.hset(record.dbkey, 'value', raw)
  FloatFieldTypeTryModel.load(record.probeid).value
end

at_exit do
  @float_field_type_try_records.each do |record|
    record.destroy!
  rescue StandardError
    nil
  end
end

# ---------------------------------------------------------------------------
# Coercion contract
# ---------------------------------------------------------------------------

## macro setter accepts only documented numeric inputs and preserves nil
FLOAT_FIELD_TYPE_COERCION_CASES.map { |input, expected| [float_field_type_try_coerce(input), expected] }
#=> [[nil, nil], [nil, nil], [17.0, 17.0], [17.9, 17.9], [1772940425.0, 1772940425.0], [41.0, 41.0], [-17.0, -17.0], [17.9, 17.9], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil]]

## assigning nil remains nil after save and reload
@float_nil_record = float_field_type_try_record
@float_nil_record.value = nil
@float_nil_record.save
[@float_nil_record.value, FloatFieldTypeTryModel.load(@float_nil_record.probeid).value]
#=> [nil, nil]

# ---------------------------------------------------------------------------
# Macro integration and native JSON storage
# ---------------------------------------------------------------------------

## setter plus save persists an unquoted native JSON float through hmget
@float_save_record = float_field_type_try_record
@float_save_record.value = '1772940425.25'
@float_save_record.save
float_field_type_try_raw_value(@float_save_record)
#=> '1772940425.25'

## value!(value) persists the same native JSON float through hmget
@float_fast_record = float_field_type_try_record
@float_fast_record.save
@float_fast_record.value!('1772940425.25')
float_field_type_try_raw_value(@float_fast_record)
#=> '1772940425.25'

## value! and value!(nil) are reads that leave native bytes untouched
[
  @float_fast_record.value!,
  @float_fast_record.value!(nil),
  float_field_type_try_raw_value(@float_fast_record),
]
#=> ['1772940425.25', '1772940425.25', '1772940425.25']

# ---------------------------------------------------------------------------
# Legacy raw storage
# ---------------------------------------------------------------------------

## legacy JSON-quoted numeric bytes load as a Float
float_field_type_try_legacy_value('"1772940425"')
#=> 1772940425.0

## legacy unquoted numeric JSON bytes load as a Float
float_field_type_try_legacy_value('1772940425')
#=> 1772940425.0

## loading a JSON-quoted legacy number then saving rewrites native JSON bytes
@float_healing_record = float_field_type_try_record
@float_healing_record.save
@float_healing_record.dbclient.hset(@float_healing_record.dbkey, 'value', '"1772940425"')
@float_healing_record = FloatFieldTypeTryModel.load(@float_healing_record.probeid)
@float_healing_record.save
float_field_type_try_raw_value(@float_healing_record)
#=> '1772940425.0'

## legacy JSON empty-string bytes load as nil
float_field_type_try_legacy_value('""')
#=> nil

## legacy JSON garbage-string bytes load as nil
float_field_type_try_legacy_value('"garbage"')
#=> nil
