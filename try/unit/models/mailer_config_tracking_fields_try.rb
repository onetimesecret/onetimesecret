# try/unit/models/mailer_config_tracking_fields_try.rb
#
# frozen_string_literal: true

# Tests for MailerConfig verification tracking fields
#
# Validates:
# 1. record_check_attempt updates all tracking fields
# 2. check_recent? returns correct results based on timing
# 3. check_count increments on each attempt
# 4. last_error is cleared on successful check
# 5. Tracking fields persist across reloads

require_relative '../../support/test_models'
require 'securerandom'

OT.boot! :test

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)
@owner = Onetime::Customer.create!(email: "track_owner_#{@ts}_#{@entropy}@test.com")
@org = Onetime::Organization.create!("Tracking Test Org #{@ts}", @owner, "track_#{@ts}@test.com")
@domain = Onetime::CustomDomain.create!("track-test-#{@ts}.example.com", @org.objid)

@config = Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  provider: 'ses',
  from_name: 'Tracking Test',
  from_address: "noreply@track-test-#{@ts}.example.com",
)

## Initial check_count is nil or 0
@config.check_count.to_i
#=> 0

## Initial last_check_at is nil or empty
@config.last_check_at.to_s.empty? || @config.last_check_at.nil?
#=> true

## record_check_attempt updates last_check_at
@before_check = Familia.now.to_i
@config.record_check_attempt(150, nil)
@config.last_check_at.to_i >= @before_check
#=> true

## record_check_attempt updates check_duration_ms
@config.check_duration_ms.to_i
#=> 150

## record_check_attempt increments check_count
@config.check_count.to_i
#=> 1

## record_check_attempt sets last_error to nil on success
@config.last_error.nil? || @config.last_error.to_s.empty?
#=> true

## Second check increments check_count to 2
@config.record_check_attempt(200, nil)
@config.check_count.to_i
#=> 2

## Duration is updated with new value
@config.check_duration_ms.to_i
#=> 200

## record_check_attempt with error sets last_error
@config.record_check_attempt(50, 'DNS timeout')
@config.last_error
#=> 'DNS timeout'

## check_count incremented even on error
@config.check_count.to_i
#=> 3

## Successful check clears last_error
@config.record_check_attempt(100, nil)
@config.last_error.to_s.empty? || @config.last_error.nil?
#=> true

## check_count now at 4
@config.check_count.to_i
#=> 4

## Tracking fields persist across reload
@reloaded = Onetime::CustomDomain::MailerConfig.find_by_domain_id(@domain.identifier)
@reloaded.check_count.to_i
#=> 4

## Reloaded last_check_at is recent
@reloaded.last_check_at.to_i > 0
#=> true

## Reloaded check_duration_ms preserved
@reloaded.check_duration_ms.to_i
#=> 100

## check_recent? returns true immediately after check
@config.check_recent?(300)
#=> true

## check_recent? returns true with default max_age
@config.check_recent?
#=> true

## check_recent? returns false when last_check_at is empty
@fresh_config = Onetime::CustomDomain::MailerConfig.new(domain_id: 'fresh-domain')
@fresh_config.check_recent?
#=> false

## check_recent? returns false for very old timestamp
@config.last_check_at = (Familia.now.to_i - 1000).to_s
@config.check_recent?(300)
#=> false

## check_recent? returns true when within window
@config.last_check_at = (Familia.now.to_i - 100).to_s
@config.check_recent?(300)
#=> true

## check_recent? with custom window works correctly
@config.last_check_at = (Familia.now.to_i - 60).to_s
@config.check_recent?(30)
#=> false

## check_recent? edge case: exactly at boundary
@config.last_check_at = (Familia.now.to_i - 300).to_s
@config.check_recent?(300)
#=> false

## Error message can be longer text
@long_error = "DNS resolution failed: Timeout::Error after 30s attempting to resolve selector1._domainkey.example.com"
@config.record_check_attempt(30000, @long_error)
@config.last_error == @long_error
#=> true

# Teardown
Familia.dbclient.flushdb
