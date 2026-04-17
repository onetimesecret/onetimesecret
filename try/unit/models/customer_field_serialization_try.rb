# try/unit/models/customer_field_serialization_try.rb
#
# frozen_string_literal: true

# Tests for raw Redis wire format of Customer email serialization.
#
# Issue #3016: migration 007 and change_email.rb were writing email fields
# to Redis as raw strings instead of JSON-serialized strings. The Familia v2
# contract requires Familia::JsonSerializer.dump(value) -- so "user@example.com"
# must be stored as '"user@example.com"' (JSON-wrapped) in Redis.
#
# These tests bypass model accessors entirely, reading raw Redis values with
# hget, because deserialize_value silently tolerates bare strings via a rescue
# fallback. That fallback masks serialization bugs -- the model accessor returns
# the correct email either way.
#
# Tests cover:
# 1. Customer fields stored as JSON in Redis (raw hget verification)
# 2. Familia::JsonSerializer.dump produces expected format for email strings
# 3. Raw (non-JSON) string is detectable as improperly serialized
# 4. Deserialize fallback handles both JSON and bare string formats
# 5. JSON parsing correctly accepts non-string JSON types (numbers, booleans, null)
# 6. Narrowed rescue catches SerializerError but not unrelated exceptions
# 7. Diagnostic properly_serialized? matches doctor properly_serialized_value?

require_relative '../../support/test_helpers'

OT.boot! :test, false

@test_id = SecureRandom.hex(6)
@redis = Familia.dbclient

# TRYOUTS

## JsonSerializer.dump wraps an email string in JSON quotes
Familia::JsonSerializer.dump("user@example.com")
#=> '"user@example.com"'

## JsonSerializer.dump output starts and ends with quote characters
dumped = Familia::JsonSerializer.dump("serialization_test@example.com")
[dumped[0], dumped[-1]]
#=> ['"', '"']

## JsonSerializer.dump round-trips with parse back to the original string
email = "roundtrip_#{@test_id}@example.com"
dumped = Familia::JsonSerializer.dump(email)
Familia::JsonSerializer.parse(dumped)
#=> "roundtrip_#{@test_id}@example.com"

## Customer.create! stores email field as JSON-wrapped string in Redis
email = "wire_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_email = @redis.hget(cust.dbkey, 'email')
cust.delete!
raw_email
#=> "\"wire_#{@test_id}@example.com\""

## Raw email value from Redis starts with a JSON quote character
email = "startquote_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_email = @redis.hget(cust.dbkey, 'email')
cust.delete!
raw_email.start_with?('"')
#=> true

## Raw email value from Redis ends with a JSON quote character
email = "endquote_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_email = @redis.hget(cust.dbkey, 'email')
cust.delete!
raw_email.end_with?('"')
#=> true

## Raw email value length is original length plus 2 (for JSON wrapping quotes)
email = "lencheck_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_email = @redis.hget(cust.dbkey, 'email')
cust.delete!
raw_email.length == email.length + 2
#=> true

## Customer.create! stores custid field as JSON-wrapped string in Redis
email = "custid_wire_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_custid = @redis.hget(cust.dbkey, 'custid')
expected = Familia::JsonSerializer.dump(cust.custid)
cust.delete!
raw_custid == expected
#=> true

## Customer.create! stores role field as JSON-wrapped string in Redis
email = "role_wire_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_role = @redis.hget(cust.dbkey, 'role')
cust.delete!
raw_role
#=> '"customer"'

## A bare string written via hset is NOT properly serialized (no JSON quotes)
email = "bare_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
# Simulate the bug: write a raw string directly (what the old code did)
@redis.hset(cust.dbkey, 'email', email)
raw_email = @redis.hget(cust.dbkey, 'email')
properly_serialized = raw_email.start_with?('"') && raw_email.end_with?('"')
cust.delete!
properly_serialized
#=> false

## A bare string in Redis still reads correctly through the model accessor (the mask)
email = "masked_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
# Write bare string to simulate the bug
@redis.hset(cust.dbkey, 'email', email)
# Reload from Redis through accessor -- deserialize_value fallback returns it as-is
reloaded = Onetime::Customer.find(cust.objid)
accessor_email = reloaded.email
cust.delete!
accessor_email == email
#=> true

## A properly serialized value can be detected by checking for JSON wrapping
email = "detect_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
raw_email = @redis.hget(cust.dbkey, 'email')
# Proper JSON string: starts and ends with quote, inner content matches email
is_json_string = raw_email.start_with?('"') &&
                 raw_email.end_with?('"') &&
                 raw_email[1..-2] == email
cust.delete!
is_json_string
#=> true

## JsonSerializer.parse correctly deserializes a JSON-quoted string
Familia::JsonSerializer.parse('"quoted@example.com"')
#=> "quoted@example.com"

## JsonSerializer.parse raises SerializerError for a bare email string
begin
  Familia::JsonSerializer.parse("bare@example.com")
  false
rescue Familia::SerializerError
  true
end
#=> true

## JsonSerializer.parse returns nil for empty string (not an error)
Familia::JsonSerializer.parse("")
#=> nil

## JsonSerializer.parse returns nil for nil input (not an error)
Familia::JsonSerializer.parse(nil)
#=> nil

## All string fields in a saved Customer are JSON-wrapped in Redis
email = "allfields_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.planid = "basic"
cust.locale = "en"
cust.save
string_fields = %w[email custid role planid locale]
raw_values = string_fields.map { |f| [f, @redis.hget(cust.dbkey, f)] }.to_h
all_json_wrapped = raw_values.all? do |field, raw|
  next true if raw.nil? || raw == 'null'
  raw.start_with?('"') && raw.end_with?('"')
end
cust.delete!
all_json_wrapped
#=> true

# ------------------------------------------------------------------
# JSON-parse-based serialization check vs old heuristic
#
# The doctor command and diagnostic script now use actual JSON parsing
# (via Familia::JsonSerializer.parse) instead of checking for wrapping
# quotes. These tests verify JSON parsing correctly identifies valid
# JSON types that the heuristic would have rejected.
# ------------------------------------------------------------------

## JSON-parse check accepts a number as properly serialized
begin
  Familia::JsonSerializer.parse("123")
  true
rescue Familia::SerializerError
  false
end
#=> true

## JSON-parse check accepts a boolean as properly serialized
begin
  Familia::JsonSerializer.parse("true")
  true
rescue Familia::SerializerError
  false
end
#=> true

## JSON-parse check accepts null as properly serialized
begin
  Familia::JsonSerializer.parse("null")
  true
rescue Familia::SerializerError
  false
end
#=> true

## JSON-parse check accepts a JSON object as properly serialized
begin
  Familia::JsonSerializer.parse('{"key":"value"}')
  true
rescue Familia::SerializerError
  false
end
#=> true

## JSON-parse check accepts a JSON array as properly serialized
begin
  Familia::JsonSerializer.parse('[1,2,3]')
  true
rescue Familia::SerializerError
  false
end
#=> true

## JSON-parse check rejects a bare email string
begin
  Familia::JsonSerializer.parse("bare@example.com")
  false
rescue Familia::SerializerError
  true
end
#=> true

## JSON-parse check rejects an unterminated quoted string
begin
  Familia::JsonSerializer.parse('"unterminated')
  false
rescue Familia::SerializerError
  true
end
#=> true

## JSON-parse check rejects a bare hostname-like string
begin
  Familia::JsonSerializer.parse("some-host.example.com")
  false
rescue Familia::SerializerError
  true
end
#=> true

# ------------------------------------------------------------------
# Narrowed rescue: SerializerError vs other exception types
#
# The migration and doctor code now rescue only JSON::ParserError and
# Familia::SerializerError. Familia::JsonSerializer.parse raises
# SerializerError (wrapping Oj errors), never JSON::ParserError.
# These tests verify the rescue specificity.
# ------------------------------------------------------------------

## SerializerError is not a subclass of JSON::ParserError
Familia::SerializerError.ancestors.include?(JSON::ParserError)
#=> false

## SerializerError is a subclass of Familia::HorreumError
Familia::SerializerError.ancestors.include?(Familia::HorreumError)
#=> true

## A rescue clause catching SerializerError does catch parse failures
caught = begin
  Familia::JsonSerializer.parse("not-json-at-all")
  :no_exception
rescue Familia::SerializerError
  :serializer_error
rescue StandardError
  :other_error
end
caught
#=> :serializer_error

## A rescue clause for SerializerError does not catch TypeError
caught = begin
  raise TypeError, "simulated type error"
rescue Familia::SerializerError
  :serializer_error
rescue TypeError
  :type_error
end
caught
#=> :type_error

## A rescue clause for SerializerError does not catch RuntimeError
caught = begin
  raise RuntimeError, "simulated runtime error"
rescue Familia::SerializerError
  :serializer_error
rescue RuntimeError
  :runtime_error
end
caught
#=> :runtime_error

# ------------------------------------------------------------------
# Diagnostic script and doctor command: properly_serialized? behavior
#
# Both use Familia::JsonSerializer.parse wrapped in a rescue block.
# These tests replicate the exact logic from both implementations.
# ------------------------------------------------------------------

## Doctor properly_serialized_value? logic returns true for JSON-quoted string
value = '"user@example.com"'
result = begin
  Familia::JsonSerializer.parse(value)
  true
rescue JSON::ParserError, Familia::SerializerError
  false
end
result
#=> true

## Doctor properly_serialized_value? logic returns false for bare string
value = 'user@example.com'
result = begin
  Familia::JsonSerializer.parse(value)
  true
rescue JSON::ParserError, Familia::SerializerError
  false
end
result
#=> false

## Doctor properly_serialized_value? logic returns true for integer value
value = '42'
result = begin
  Familia::JsonSerializer.parse(value)
  true
rescue JSON::ParserError, Familia::SerializerError
  false
end
result
#=> true

## Doctor properly_serialized_value? logic returns true for boolean value
value = 'false'
result = begin
  Familia::JsonSerializer.parse(value)
  true
rescue JSON::ParserError, Familia::SerializerError
  false
end
result
#=> true

## Doctor properly_serialized_value? logic returns true for JSON object
value = '{"planid":"basic"}'
result = begin
  Familia::JsonSerializer.parse(value)
  true
rescue JSON::ParserError, Familia::SerializerError
  false
end
result
#=> true

## Diagnostic properly_serialized? returns true for nil (early return)
value = nil
result = if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  true
else
  begin
    Familia::JsonSerializer.parse(value)
    true
  rescue JSON::ParserError, Familia::SerializerError
    false
  end
end
result
#=> true

## Diagnostic properly_serialized? returns true for empty string (early return)
value = ''
result = if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  true
else
  begin
    Familia::JsonSerializer.parse(value)
    true
  rescue JSON::ParserError, Familia::SerializerError
    false
  end
end
result
#=> true

# ------------------------------------------------------------------
# Migration rescue narrowing: JSON.parse vs Familia::JsonSerializer.parse
#
# The migration uses JSON.parse for objid_json (line 119) which raises
# JSON::ParserError, and Familia::JsonSerializer.parse for stored_email
# (lines 133-134, 152-153) which raises Familia::SerializerError.
# These tests verify both exception types are handled correctly.
# ------------------------------------------------------------------

## JSON.parse raises JSON::ParserError for invalid JSON (migration objid path)
begin
  JSON.parse("not-valid-json")
  :no_exception
rescue JSON::ParserError
  :parser_error
end
#=> :parser_error

## JSON.parse succeeds for a JSON-quoted string (migration objid path)
JSON.parse('"some-objid-value"')
#=> "some-objid-value"

## Migration fallback: JSON.parse failure falls back to raw value
objid_json = "raw-objid-no-quotes"
objid = begin
  JSON.parse(objid_json)
rescue JSON::ParserError
  objid_json
end
objid
#=> "raw-objid-no-quotes"

## Migration email parse: Familia serializer parse with fallback to raw
stored_email_raw = "user@example.com"
stored_email = begin
  Familia::JsonSerializer.parse(stored_email_raw)
rescue JSON::ParserError, Familia::SerializerError
  stored_email_raw
end
stored_email
#=> "user@example.com"

## Migration email parse: properly serialized email is unwrapped
stored_email_raw = '"user@example.com"'
stored_email = begin
  Familia::JsonSerializer.parse(stored_email_raw)
rescue JSON::ParserError, Familia::SerializerError
  stored_email_raw
end
stored_email
#=> "user@example.com"
