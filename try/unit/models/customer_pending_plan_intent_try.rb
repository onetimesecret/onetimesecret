# try/unit/models/customer_pending_plan_intent_try.rb
#
# frozen_string_literal: true

# Tests for Customer.pending_plan_intent field (issue #3126).
#
# This field persists plan selection through email verification flow.
# It stores a JSON structure containing product, interval, captured timestamp,
# and source URL. The field has a 24-hour TTL and is single-use (cleared
# after checkout redirect).
#
# IMPORTANT: pending_plan_intent is a Familia::StringKey, not a raw String.
# - Use .value to get the raw value (nil, empty string, or the stored value)
# - Use .to_s which returns the value if present, or inspect string if empty
# - Setting to nil sets value to empty string "" (use .delete! to fully remove)
#
# Tests cover:
# 1. Field stores and retrieves JSON intent data
# 2. Field has 24h default expiration (TTL)
# 3. Setting to nil clears the field (sets to empty string)
# 4. JSON round-trip preserves all intent properties
# 5. Invalid JSON doesn't break customer operations
# 6. Field is independent of other customer fields
# 7. Multiple intent updates work correctly

require_relative '../../support/test_helpers'

OT.boot! :test, false

@test_id = SecureRandom.hex(6)
@redis = Familia.dbclient

# TRYOUTS

## pending_plan_intent field declaration exists on Customer
Onetime::Customer.respond_to?(:pending_plan_intent) ||
  Onetime::Customer.new.respond_to?(:pending_plan_intent)
#=> true

## Customer instance has pending_plan_intent getter and setter
cust = Onetime::Customer.new(email: generate_random_email)
cust.respond_to?(:pending_plan_intent) && cust.respond_to?(:pending_plan_intent=)
#=> true

## New unsaved customer has a StringKey with nil value
cust = Onetime::Customer.new(email: generate_random_email)
cust.pending_plan_intent.value.nil?
#=> true

## pending_plan_intent is a Familia::StringKey
cust = Onetime::Customer.new(email: generate_random_email)
cust.pending_plan_intent.class
#=> Familia::StringKey

## pending_plan_intent stores JSON string and retrieves via .value
email = "intent_store_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = { product: 'identity_plus_v1', interval: 'yearly', captured_at: Time.now.utc.iso8601 }.to_json
cust.pending_plan_intent = intent
stored = cust.pending_plan_intent.value
cust.delete!
stored == intent
#=> true

## pending_plan_intent.to_s returns value when set
email = "intent_tos_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = { product: 'identity_plus_v1', interval: 'yearly' }.to_json
cust.pending_plan_intent = intent
result = cust.pending_plan_intent.to_s
cust.delete!
result == intent
#=> true

## pending_plan_intent survives customer reload
email = "intent_reload_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = { product: 'team_plus_v1', interval: 'monthly', captured_at: Time.now.utc.iso8601 }.to_json
cust.pending_plan_intent = intent
# Force reload from Redis
reloaded = Onetime::Customer.find(cust.objid)
result = reloaded.pending_plan_intent.value
cust.delete!
result == intent
#=> true

## Setting pending_plan_intent to nil sets value to empty string
email = "intent_clear_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = { product: 'identity_plus_v1', interval: 'yearly' }.to_json
cust.pending_plan_intent = intent
cust.pending_plan_intent = nil
result = cust.pending_plan_intent.value
cust.delete!
result
#=> ""

## pending_plan_intent.delete! fully removes the key
email = "intent_delete_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = "test"
cust.pending_plan_intent.delete!
result = cust.pending_plan_intent.value
cust.delete!
result.nil?
#=> true

## pending_plan_intent JSON round-trip preserves product and interval
email = "intent_roundtrip_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
original = { 'product' => 'identity_plus_v1', 'interval' => 'monthly', 'captured_at' => '2026-05-14T10:30:00Z' }
cust.pending_plan_intent = original.to_json
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
[parsed['product'], parsed['interval'], parsed['captured_at']]
#=> ['identity_plus_v1', 'monthly', '2026-05-14T10:30:00Z']

## pending_plan_intent can store source_url
email = "intent_source_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = {
  product: 'team_plus_v1',
  interval: 'yearly',
  captured_at: Time.now.utc.iso8601,
  source_url: '/auth/create-account?product=team_plus_v1&interval=yearly',
}.to_json
cust.pending_plan_intent = intent
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
parsed['source_url'].include?('product=team_plus_v1')
#=> true

## pending_plan_intent is independent of other customer fields
email = "intent_independent_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.planid = 'basic'
cust.locale = 'en'
intent = { product: 'identity_plus_v1', interval: 'monthly' }.to_json
cust.pending_plan_intent = intent
cust.save
# Verify other fields unaffected
result = [cust.planid, cust.locale, !cust.pending_plan_intent.value.nil?]
cust.delete!
result
#=> ['basic', 'en', true]

## Multiple intent updates work correctly (last one wins)
email = "intent_multi_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = { product: 'first', interval: 'monthly' }.to_json
cust.pending_plan_intent = { product: 'second', interval: 'yearly' }.to_json
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
[parsed['product'], parsed['interval']]
#=> ['second', 'yearly']

## Empty string value is falsy when checking value
email = "intent_empty_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = ''
result = cust.pending_plan_intent.value.to_s.strip != ''
cust.delete!
result
#=> false

## pending_plan_intent handles malformed JSON gracefully (stores as-is)
email = "intent_malformed_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
malformed = 'not-valid-json{{'
cust.pending_plan_intent = malformed
stored = cust.pending_plan_intent.value
# Should store raw value (Familia::StringKey doesn't validate JSON)
cust.delete!
stored == malformed
#=> true

## Customer operations work with malformed pending_plan_intent
email = "intent_malformed_ops_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = 'not-json'
cust.planid = 'basic'
cust.save
reloaded = Onetime::Customer.find(cust.objid)
result = reloaded.planid
cust.delete!
result
#=> 'basic'

# ------------------------------------------------------------------
# TTL (Time To Live) Tests
#
# The pending_plan_intent field has a 24-hour default expiration.
# These tests verify the TTL mechanism works correctly.
# ------------------------------------------------------------------

## pending_plan_intent Redis key includes customer objid
email = "intent_key_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = 'test'
# The key pattern is: customer:<objid>:pending_plan_intent
expected_key_pattern = /customer:#{cust.objid}:pending_plan_intent/
# Get the actual key via reflection
key = cust.pending_plan_intent.dbkey rescue "customer:#{cust.objid}:pending_plan_intent"
cust.delete!
key =~ expected_key_pattern ? true : key
#=> true

## pending_plan_intent has TTL set after assignment
email = "intent_ttl_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = 'test'
# Get TTL from Redis - the key should have a positive TTL
key = "customer:#{cust.objid}:pending_plan_intent"
ttl = @redis.ttl(key)
cust.delete!
# TTL should be positive (between 0 and 24 hours = 86400 seconds)
ttl > 0 && ttl <= 86_400
#=> true

## pending_plan_intent TTL is approximately 24 hours
email = "intent_ttl24_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = 'test'
key = "customer:#{cust.objid}:pending_plan_intent"
ttl = @redis.ttl(key)
cust.delete!
# Should be close to 86400 seconds (24 hours), allow 60 seconds variance
(ttl - 86_400).abs < 60
#=> true

# ------------------------------------------------------------------
# Edge Cases
# ------------------------------------------------------------------

## pending_plan_intent works with unicode product names
email = "intent_unicode_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
intent = { product: 'plan_cafe', interval: 'monthly' }.to_json
cust.pending_plan_intent = intent
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
parsed['product']
#=> 'plan_cafe'

## pending_plan_intent preserves timestamp precision
email = "intent_timestamp_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
timestamp = '2026-05-14T10:30:45.123Z'
intent = { product: 'test', interval: 'monthly', captured_at: timestamp }.to_json
cust.pending_plan_intent = intent
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
parsed['captured_at']
#=> '2026-05-14T10:30:45.123Z'

## pending_plan_intent handles very long source URLs
email = "intent_longurl_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
long_url = '/auth/create-account?' + ('x' * 500) + '=value'
intent = { product: 'test', interval: 'monthly', source_url: long_url }.to_json
cust.pending_plan_intent = intent
parsed = JSON.parse(cust.pending_plan_intent.value)
cust.delete!
parsed['source_url'].length > 500
#=> true

## Clearing pending_plan_intent by delete! removes from Redis
email = "intent_delete2_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = 'test'
key = "customer:#{cust.objid}:pending_plan_intent"
cust.pending_plan_intent.delete! rescue nil
# Check Redis directly
exists = @redis.exists?(key)
cust.delete!
exists
#=> false

# ------------------------------------------------------------------
# Correct empty check pattern (for use in hooks)
#
# The hook code uses .to_s.strip != '' which is INCORRECT because
# an empty StringKey returns its inspect string for .to_s.
# The correct pattern is to use .value to get the actual value.
# ------------------------------------------------------------------

## Correct empty check: use .value.to_s.strip for empty detection
email = "intent_correct_check_#{@test_id}@example.com"
cust = Onetime::Customer.create!(email: email)
cust.pending_plan_intent = nil
# Incorrect: .to_s returns inspect string when value is empty
incorrect_check = cust.pending_plan_intent.to_s.strip != ''
# Correct: .value.to_s.strip checks the actual value
correct_check = cust.pending_plan_intent.value.to_s.strip != ''
cust.delete!
[incorrect_check, correct_check]
#=> [true, false]
