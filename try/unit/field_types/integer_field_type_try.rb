# try/unit/field_types/integer_field_type_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'
require 'onetime/field_types'

OT.boot! :test, false

class IntegerFieldTypeTryToIValue
  def initialize(value)
    @value = value
  end

  def to_i
    @value
  end
end

class IntegerFieldTypeTryModel < ::Familia::Horreum
  extend Onetime::FieldTypes::Macros

  prefix :try_integer_field_type
  identifier_field :probeid
  field :probeid
  integer_field :value
end

INTEGER_FIELD_TYPE_EPOCH = 1_772_940_425

INTEGER_FIELD_TYPE_COERCION_CASES = [
  [nil, nil],
  ['', nil],
  [17, 17],
  [17.9, 17],
  [Time.at(INTEGER_FIELD_TYPE_EPOCH), INTEGER_FIELD_TYPE_EPOCH],
  [IntegerFieldTypeTryToIValue.new(41), 41],
  ['  -17  ', -17],
  ['  17.9  ', 17],
  ['+17', nil],
  ['17.', nil],
  ['.17', nil],
  ['1e3', nil],
  ['- 17', nil],
  ['garbage', nil],
  [Object.new, nil],
].freeze

@integer_field_type_try_records = []

def integer_field_type_try_record
  record = IntegerFieldTypeTryModel.new(probeid: "integer-#{SecureRandom.hex(8)}")
  @integer_field_type_try_records << record
  record
end

def integer_field_type_try_coerce(value)
  record = integer_field_type_try_record
  record.value = value
  record.value
end

def integer_field_type_try_raw_value(record)
  record.dbclient.hmget(record.dbkey, 'value').first
end

def integer_field_type_try_legacy_value(raw)
  record = integer_field_type_try_record
  record.save
  record.dbclient.hset(record.dbkey, 'value', raw)
  IntegerFieldTypeTryModel.load(record.probeid).value
end

at_exit do
  @integer_field_type_try_records.each do |record|
    record.destroy!
  rescue StandardError
    nil
  end
end

# ---------------------------------------------------------------------------
# Coercion contract
# ---------------------------------------------------------------------------

## macro setter accepts only documented numeric inputs and preserves nil
INTEGER_FIELD_TYPE_COERCION_CASES.map { |input, expected| [integer_field_type_try_coerce(input), expected] }
#=> [[nil, nil], [nil, nil], [17, 17], [17, 17], [1772940425, 1772940425], [41, 41], [-17, -17], [17, 17], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil], [nil, nil]]

## assigning nil remains nil after save and reload
@integer_nil_record = integer_field_type_try_record
@integer_nil_record.value = nil
@integer_nil_record.save
[@integer_nil_record.value, IntegerFieldTypeTryModel.load(@integer_nil_record.probeid).value]
#=> [nil, nil]

# ---------------------------------------------------------------------------
# Macro integration and native JSON storage
# ---------------------------------------------------------------------------

## setter plus save persists an unquoted native JSON integer through hmget
@integer_save_record = integer_field_type_try_record
@integer_save_record.value = '1772940425.9'
@integer_save_record.save
integer_field_type_try_raw_value(@integer_save_record)
#=> '1772940425'

## value!(value) persists the same native JSON integer through hmget
@integer_fast_record = integer_field_type_try_record
@integer_fast_record.save
@integer_fast_record.value!('1772940425.9')
integer_field_type_try_raw_value(@integer_fast_record)
#=> '1772940425'

## value! and value!(nil) are reads that leave native bytes untouched
[
  @integer_fast_record.value!,
  @integer_fast_record.value!(nil),
  integer_field_type_try_raw_value(@integer_fast_record),
]
#=> ['1772940425', '1772940425', '1772940425']

# ---------------------------------------------------------------------------
# Legacy raw storage
# ---------------------------------------------------------------------------

## legacy JSON-quoted numeric bytes load as an Integer
integer_field_type_try_legacy_value('"1772940425"')
#=> 1772940425

## legacy unquoted numeric JSON bytes load as an Integer
integer_field_type_try_legacy_value('1772940425')
#=> 1772940425

## loading a JSON-quoted legacy number then saving rewrites native JSON bytes
@integer_healing_record = integer_field_type_try_record
@integer_healing_record.save
@integer_healing_record.dbclient.hset(@integer_healing_record.dbkey, 'value', '"1772940425"')
@integer_healing_record = IntegerFieldTypeTryModel.load(@integer_healing_record.probeid)
@integer_healing_record.save
integer_field_type_try_raw_value(@integer_healing_record)
#=> '1772940425'

## legacy JSON empty-string bytes load as nil
integer_field_type_try_legacy_value('""')
#=> nil

## legacy JSON garbage-string bytes load as nil
integer_field_type_try_legacy_value('"garbage"')
#=> nil
