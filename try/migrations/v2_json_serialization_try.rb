# try/migrations/v2_json_serialization_try.rb
#
# frozen_string_literal: true

# Test coverage for migration transform script v2 JSON serialization logic.
#
# The migration scripts (transform.rb) use `serialize_for_v2` and `parse_to_ruby_type`
# to convert v1 Redis hash values (all strings) to Familia v2 JSON-encoded format.
#
# Key behaviors tested:
# - Empty string '' -> JSON 'null'
# - String values -> JSON-quoted strings (e.g., 'hello' -> '"hello"')
# - Integer fields -> JSON numbers (e.g., '42' -> '42')
# - Boolean fields -> JSON booleans (e.g., 'true' -> 'true')
# - Timestamp fields -> JSON floats (e.g., '1706745600.123' -> '1706745600.123')
# - Unknown fields -> raises ArgumentError (fail-fast)

require 'familia'

# Standalone test class that mirrors the migration script logic
# without requiring the full migration script infrastructure
class V2SerializationTestHelper
  # Field type mappings - subset covering all types for testing
  FIELD_TYPES = {
    'email' => :string,
    'custid' => :string,
    'planid' => :string,
    'secrets_created' => :integer,
    'emails_sent' => :integer,
    'created' => :timestamp,
    'updated' => :timestamp,
    'verified' => :boolean,
    'notify_on_reveal' => :boolean,
  }.freeze

  class << self
    def serialize_for_v2(fields)
      fields.each_with_object({}) do |(key, value), result|
        result[key] = if value == ''
                        'null'
                      else
                        ruby_val = parse_to_ruby_type(key, value)
                        Familia::JsonSerializer.dump(ruby_val)
                      end
      end
    end

    def parse_to_ruby_type(key, value)
      field_type = FIELD_TYPES[key.to_s]
      raise ArgumentError, "Unknown field '#{key}' not in FIELD_TYPES - add it to the mapping" unless field_type

      case field_type
      when :string then value
      when :integer then value.to_i
      when :float, :timestamp then value.to_f
      when :boolean then value == 'true'
      else
        raise ArgumentError, "Unknown field type '#{field_type}' for field '#{key}'"
      end
    end
  end
end

## Empty string serializes to JSON null
V2SerializationTestHelper.serialize_for_v2({ 'email' => '' })
#=> { 'email' => 'null' }

## String value serializes to JSON-quoted string
V2SerializationTestHelper.serialize_for_v2({ 'email' => 'test@example.com' })
#=> { 'email' => '"test@example.com"' }

## String with special characters is properly JSON-escaped
V2SerializationTestHelper.serialize_for_v2({ 'email' => 'test"quote@example.com' })
#=> { 'email' => '"test\\"quote@example.com"' }

## Integer field converts string to JSON number
V2SerializationTestHelper.serialize_for_v2({ 'secrets_created' => '42' })
#=> { 'secrets_created' => '42' }

## Integer field with zero
V2SerializationTestHelper.serialize_for_v2({ 'secrets_created' => '0' })
#=> { 'secrets_created' => '0' }

## Boolean true converts to JSON boolean
V2SerializationTestHelper.serialize_for_v2({ 'verified' => 'true' })
#=> { 'verified' => 'true' }

## Boolean false converts to JSON boolean
V2SerializationTestHelper.serialize_for_v2({ 'verified' => 'false' })
#=> { 'verified' => 'false' }

## Boolean with non-standard value treats as false
V2SerializationTestHelper.serialize_for_v2({ 'verified' => 'yes' })
#=> { 'verified' => 'false' }

## Timestamp serializes as JSON float
V2SerializationTestHelper.serialize_for_v2({ 'created' => '1706745600.123' })
#=> { 'created' => '1706745600.123' }

## Timestamp integer string serializes as float
V2SerializationTestHelper.serialize_for_v2({ 'created' => '1706745600' })
#=> { 'created' => '1706745600.0' }

## Multiple fields serialize correctly together
@multi_result = V2SerializationTestHelper.serialize_for_v2({
  'email' => 'user@test.com',
  'secrets_created' => '10',
  'verified' => 'true',
  'created' => '1706745600.5',
})
@multi_result['email']
#=> '"user@test.com"'

## Multiple fields - integer field
@multi_result['secrets_created']
#=> '10'

## Multiple fields - boolean field
@multi_result['verified']
#=> 'true'

## Multiple fields - timestamp field
@multi_result['created']
#=> '1706745600.5'

## Unknown field raises ArgumentError with helpful message
begin
  V2SerializationTestHelper.serialize_for_v2({ 'unknown_field' => 'value' })
  false
rescue ArgumentError => e
  e.message.include?('Unknown field') && e.message.include?('unknown_field')
end
#=> true

## parse_to_ruby_type returns string for string type
V2SerializationTestHelper.parse_to_ruby_type('email', 'test@example.com')
#=> 'test@example.com'

## parse_to_ruby_type returns integer for integer type
V2SerializationTestHelper.parse_to_ruby_type('secrets_created', '42')
#=> 42

## parse_to_ruby_type returns float for timestamp type
V2SerializationTestHelper.parse_to_ruby_type('created', '1706745600.123')
#=> 1706745600.123

## parse_to_ruby_type returns true for boolean 'true'
V2SerializationTestHelper.parse_to_ruby_type('verified', 'true')
#=> true

## parse_to_ruby_type returns false for boolean 'false'
V2SerializationTestHelper.parse_to_ruby_type('verified', 'false')
#=> false

## parse_to_ruby_type returns false for any non-'true' boolean value
V2SerializationTestHelper.parse_to_ruby_type('verified', 'whatever')
#=> false

## Familia JsonSerializer.dump produces expected output for string
Familia::JsonSerializer.dump('hello')
#=> '"hello"'

## Familia JsonSerializer.dump produces expected output for integer
Familia::JsonSerializer.dump(42)
#=> '42'

## Familia JsonSerializer.dump produces expected output for float
Familia::JsonSerializer.dump(1706745600.123)
#=> '1706745600.123'

## Familia JsonSerializer.dump produces expected output for true
Familia::JsonSerializer.dump(true)
#=> 'true'

## Familia JsonSerializer.dump produces expected output for false
Familia::JsonSerializer.dump(false)
#=> 'false'

## Familia JsonSerializer.dump produces expected output for nil
Familia::JsonSerializer.dump(nil)
#=> 'null'
