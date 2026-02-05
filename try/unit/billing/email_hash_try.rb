# try/unit/billing/email_hash_try.rb
#
# frozen_string_literal: true

# Tests HMAC email hashing for cross-region subscription federation.
#
# Run: bundle exec try try/unit/billing/email_hash_try.rb

require_relative '../../support/test_helpers'
require 'onetime/utils/email_hash'

# Setup: Set a test secret for HMAC computation
@original_secret = ENV['FEDERATION_HMAC_SECRET']
ENV['FEDERATION_HMAC_SECRET'] = 'test-secret-for-email-hash-federation-12345'

## Compute returns nil for empty email
Onetime::Utils::EmailHash.compute('')
#=> nil

## Compute returns nil for nil email
Onetime::Utils::EmailHash.compute(nil)
#=> nil

## Compute returns nil for whitespace-only email
Onetime::Utils::EmailHash.compute('   ')
#=> nil

## Compute returns a 32-character hex string
hash = Onetime::Utils::EmailHash.compute('test@example.com')
[hash.length, hash.match?(/\A[a-f0-9]+\z/)]
#=> [32, true]

## Compute is case-insensitive
hash1 = Onetime::Utils::EmailHash.compute('Alice@Example.com')
hash2 = Onetime::Utils::EmailHash.compute('alice@example.com')
hash1 == hash2
#=> true

## Compute normalizes whitespace
hash1 = Onetime::Utils::EmailHash.compute('  test@example.com  ')
hash2 = Onetime::Utils::EmailHash.compute('test@example.com')
hash1 == hash2
#=> true

## Compute produces different hashes for different emails
hash1 = Onetime::Utils::EmailHash.compute('alice@example.com')
hash2 = Onetime::Utils::EmailHash.compute('bob@example.com')
hash1 != hash2
#=> true

## Compute is deterministic (same email, same hash)
hash1 = Onetime::Utils::EmailHash.compute('deterministic@test.com')
hash2 = Onetime::Utils::EmailHash.compute('deterministic@test.com')
hash1 == hash2
#=> true

## same_hash? returns true for matching emails
Onetime::Utils::EmailHash.same_hash?('test@example.com', 'TEST@EXAMPLE.COM')
#=> true

## same_hash? returns false for different emails
Onetime::Utils::EmailHash.same_hash?('alice@example.com', 'bob@example.com')
#=> false

## same_hash? returns false when first email is empty
Onetime::Utils::EmailHash.same_hash?('', 'test@example.com')
#=> false

## same_hash? returns false when second email is empty
Onetime::Utils::EmailHash.same_hash?('test@example.com', '')
#=> false

## same_hash? returns false for nil emails
Onetime::Utils::EmailHash.same_hash?(nil, nil)
#=> false

## Compute raises error when secret is not configured
original = ENV['FEDERATION_HMAC_SECRET']
ENV['FEDERATION_HMAC_SECRET'] = nil
begin
  Onetime::Utils::EmailHash.compute('test@example.com')
  :no_error
rescue Onetime::Problem => e
  e.message.include?('FEDERATION_HMAC_SECRET')
ensure
  ENV['FEDERATION_HMAC_SECRET'] = original
end
#=> true

## Hash is different with different secrets
ENV['FEDERATION_HMAC_SECRET'] = 'secret-one'
hash1 = Onetime::Utils::EmailHash.compute('test@example.com')
ENV['FEDERATION_HMAC_SECRET'] = 'secret-two'
hash2 = Onetime::Utils::EmailHash.compute('test@example.com')
ENV['FEDERATION_HMAC_SECRET'] = @original_secret || 'test-secret-for-email-hash-federation-12345'
hash1 != hash2
#=> true

# Teardown: Restore original secret
ENV['FEDERATION_HMAC_SECRET'] = @original_secret
