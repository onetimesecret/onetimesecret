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
