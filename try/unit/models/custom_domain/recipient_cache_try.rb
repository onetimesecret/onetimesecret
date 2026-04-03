# try/unit/models/custom_domain/recipient_cache_try.rb
#
# frozen_string_literal: true

#
# CustomDomain Recipient Cache Test Suite
# Tests caching behavior for incoming recipient lookup and public recipients.
#
# Issue #2863: Cache recipient lookup to avoid recomputing SHA256 hashes
# on every request. These tests verify:
# - Basic functionality returns correct data
# - Caching behavior (same object returned on subsequent calls)
# - Cache keying by site_secret
# - Cache invalidation on config update
# - Frozen objects for thread safety
#

require_relative '../../../support/test_helpers'

require 'onetime'

OT.boot! :test

# Clean up any existing test data from previous runs
Familia.dbclient.flushdb
OT.info "Cleaned Redis for fresh test run"

# Setup test fixtures
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "cache_test_owner_#{@timestamp}@test.com")
@org = Onetime::Organization.create!("Cache Test Org", @owner, "cache@test.com")
@domain = Onetime::CustomDomain.create!("cache-test-#{@timestamp}.example.com", @org.objid)
@site_secret = "test_site_secret_#{@timestamp}"

# Configure recipients for the domain
@recipients_data = [
  { 'email' => 'support@cache-test.com', 'name' => 'Support Team' },
  { 'email' => 'admin@cache-test.com', 'name' => 'Admin' },
  { 'email' => 'sales@cache-test.com', 'name' => 'Sales Department' }
]
@config = Onetime::CustomDomain::IncomingSecretsConfig.new({ 'recipients' => @recipients_data })
@domain.update_incoming_secrets_config(@config)

# Reload to ensure we're testing with fresh state
@domain = Onetime::CustomDomain.load_by_display_domain(@domain.display_domain)

## cached_incoming_recipient_lookup returns a hash
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup.is_a?(Hash)
#=> true

## cached_incoming_recipient_lookup contains correct number of entries
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup.size
#=> 3

## cached_incoming_recipient_lookup maps hashes to email addresses
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup.values.sort
#=> ['admin@cache-test.com', 'sales@cache-test.com', 'support@cache-test.com']

## cached_incoming_recipient_lookup keys are SHA256 hashes (64 hex chars)
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup.keys.all? { |k| k.match?(/\A[a-f0-9]{64}\z/) }
#=> true

## cached_incoming_recipient_lookup hash keys match expected format
expected_hash = Digest::SHA256.hexdigest("support@cache-test.com:#{@site_secret}")
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup[expected_hash]
#=> 'support@cache-test.com'

## cached_public_incoming_recipients returns an array
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.is_a?(Array)
#=> true

## cached_public_incoming_recipients contains correct number of entries
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.size
#=> 3

## cached_public_incoming_recipients entries have hash and name keys
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.all? { |r| r.key?('hash') && r.key?('name') }
#=> true

## cached_public_incoming_recipients does not expose email addresses
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.none? { |r| r.key?('email') }
#=> true

## cached_public_incoming_recipients names are correct
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.map { |r| r['name'] }.sort
#=> ['Admin', 'Sales Department', 'Support Team']

## cached_public_incoming_recipients hashes are SHA256 format
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.all? { |r| r['hash'].match?(/\A[a-f0-9]{64}\z/) }
#=> true

## Caching: second call returns same object (object_id equality) for lookup
first_call = @domain.cached_incoming_recipient_lookup(@site_secret)
second_call = @domain.cached_incoming_recipient_lookup(@site_secret)
first_call.object_id == second_call.object_id
#=> true

## Caching: second call returns same object (object_id equality) for public recipients
first_call = @domain.cached_public_incoming_recipients(@site_secret)
second_call = @domain.cached_public_incoming_recipients(@site_secret)
first_call.object_id == second_call.object_id
#=> true

## Cache is keyed by site_secret: different secrets yield different cache entries
@alt_secret = "alternative_secret_#{@timestamp}"
lookup1 = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup2 = @domain.cached_incoming_recipient_lookup(@alt_secret)
lookup1.object_id != lookup2.object_id
#=> true

## Cache keying: different secrets produce different hash values
lookup1 = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup2 = @domain.cached_incoming_recipient_lookup(@alt_secret)
lookup1.keys.sort != lookup2.keys.sort
#=> true

## Cache keying: both lookups still map to same emails
lookup1 = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup2 = @domain.cached_incoming_recipient_lookup(@alt_secret)
lookup1.values.sort == lookup2.values.sort
#=> true

## Cache keying: public recipients also keyed by secret
public1 = @domain.cached_public_incoming_recipients(@site_secret)
public2 = @domain.cached_public_incoming_recipients(@alt_secret)
public1.object_id != public2.object_id
#=> true

## Frozen: cached_incoming_recipient_lookup returns frozen hash
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
lookup.frozen?
#=> true

## Frozen: cached_public_incoming_recipients returns frozen array
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_recipients.frozen?
#=> true

## Frozen: attempting to mutate lookup hash raises FrozenError
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
begin
  lookup['new_key'] = 'new_value'
  false
rescue FrozenError
  true
end
#=> true

## Frozen: attempting to mutate public recipients array raises FrozenError
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
begin
  public_recipients << { 'hash' => 'fake', 'name' => 'Fake' }
  false
rescue FrozenError
  true
end
#=> true

## Cache invalidation: update_incoming_secrets_config clears lookup cache
# First, populate the cache
old_lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
old_object_id = old_lookup.object_id
# Update config (this should clear caches)
@new_config = Onetime::CustomDomain::IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'new@cache-test.com', 'name' => 'New Recipient' }
  ]
})
@domain.update_incoming_secrets_config(@new_config)
# New call should return different object
new_lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
old_object_id != new_lookup.object_id
#=> true

## Cache invalidation: new lookup has updated data
new_lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
new_lookup.values
#=> ['new@cache-test.com']

## Cache invalidation: public recipients also cleared
@domain = Onetime::CustomDomain.load_by_display_domain(@domain.display_domain)
@updated_config = Onetime::CustomDomain::IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'updated@cache-test.com', 'name' => 'Updated Recipient' }
  ]
})
# Populate cache first
old_public = @domain.cached_public_incoming_recipients(@site_secret)
old_public_id = old_public.object_id
# Update config
@domain.update_incoming_secrets_config(@updated_config)
# New call should return different object with new data
new_public = @domain.cached_public_incoming_recipients(@site_secret)
[old_public_id != new_public.object_id, new_public.first['name']]
#=> [true, 'Updated Recipient']

## Empty recipients: cached_incoming_recipient_lookup returns empty hash
@empty_config = Onetime::CustomDomain::IncomingSecretsConfig.new({ 'recipients' => [] })
@domain.update_incoming_secrets_config(@empty_config)
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
[lookup.is_a?(Hash), lookup.empty?, lookup.frozen?]
#=> [true, true, true]

## Empty recipients: cached_public_incoming_recipients returns empty array
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
[public_recipients.is_a?(Array), public_recipients.empty?, public_recipients.frozen?]
#=> [true, true, true]

## Consistency: lookup hash matches public recipients by hash key
@consistency_config = Onetime::CustomDomain::IncomingSecretsConfig.new({
  'recipients' => [
    { 'email' => 'verify@cache-test.com', 'name' => 'Verify User' }
  ]
})
@domain.update_incoming_secrets_config(@consistency_config)
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
# The hash in public_recipients should exist as a key in lookup
public_hash = public_recipients.first['hash']
lookup.key?(public_hash)
#=> true

## Consistency: can resolve email from public recipient hash
lookup = @domain.cached_incoming_recipient_lookup(@site_secret)
public_recipients = @domain.cached_public_incoming_recipients(@site_secret)
public_hash = public_recipients.first['hash']
lookup[public_hash]
#=> 'verify@cache-test.com'

# Teardown
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
