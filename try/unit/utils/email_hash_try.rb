# try/unit/utils/email_hash_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::Utils::EmailHash - HMAC-based email hashing for
# subscription federation (#2471).
#
# EmailHash provides deterministic, non-reversible email identification
# for cross-region subscription federation without exposing email addresses.
#
# Security model:
# - Hash is computed at subscription creation and stored immutably in Stripe metadata
# - Email changes post-subscription do NOT update the hash (prevents email-swap attacks)
# - Uses HMAC-SHA256 with FEDERATION_SECRET for domain separation
#
# Run: pnpm run test:tryouts:agent try/unit/utils/email_hash_try.rb

require_relative '../../support/test_helpers'

# Stub the HMAC secret for testing (must be set before EmailHash is loaded)
ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-email-hash-32chars'

require 'onetime/utils/email_hash'

# Test data
@test_email = 'user@example.com'
@test_email_upper = 'USER@EXAMPLE.COM'
@test_email_whitespace = '  user@example.com  '
@different_email = 'other@example.com'

## EmailHash.compute returns a string
hash = Onetime::Utils::EmailHash.compute(@test_email)
hash.is_a?(String)
#=> true

## Hash is 32 hexadecimal characters (128 bits)
hash = Onetime::Utils::EmailHash.compute(@test_email)
hash.length
#=> 32

## Hash contains only hex characters
hash = Onetime::Utils::EmailHash.compute(@test_email)
hash =~ /^[a-f0-9]{32}$/
#=> 0

## Same email produces same hash (deterministic)
hash1 = Onetime::Utils::EmailHash.compute(@test_email)
hash2 = Onetime::Utils::EmailHash.compute(@test_email)
hash1 == hash2
#=> true

## Email normalization: case-insensitive (uppercase produces same hash)
hash_lower = Onetime::Utils::EmailHash.compute(@test_email)
hash_upper = Onetime::Utils::EmailHash.compute(@test_email_upper)
hash_lower == hash_upper
#=> true

## Email normalization: whitespace is trimmed
hash_clean = Onetime::Utils::EmailHash.compute(@test_email)
hash_whitespace = Onetime::Utils::EmailHash.compute(@test_email_whitespace)
hash_clean == hash_whitespace
#=> true

## Different emails produce different hashes
hash1 = Onetime::Utils::EmailHash.compute(@test_email)
hash2 = Onetime::Utils::EmailHash.compute(@different_email)
hash1 != hash2
#=> true

## Empty string returns nil
Onetime::Utils::EmailHash.compute('')
#=> nil

## Nil email returns nil
Onetime::Utils::EmailHash.compute(nil)
#=> nil

## Whitespace-only email returns nil
Onetime::Utils::EmailHash.compute('   ')
#=> nil

## Hash is lowercase hex
hash = Onetime::Utils::EmailHash.compute(@test_email)
hash == hash.downcase
#=> true

## Complex email addresses are handled correctly
complex_email = 'user+tag@sub.example.co.uk'
hash = Onetime::Utils::EmailHash.compute(complex_email)
hash =~ /^[a-f0-9]{32}$/
#=> 0

## Unicode email addresses are handled correctly
unicode_email = 'user@example.com'
hash = Onetime::Utils::EmailHash.compute(unicode_email)
hash =~ /^[a-f0-9]{32}$/
#=> 0

## Missing HMAC secret raises configuration error
# Save and clear the secret
original_secret = ENV['FEDERATION_SECRET']
ENV.delete('FEDERATION_SECRET')
begin
  # Re-require to pick up the missing secret (or check at compute time)
  Onetime::Utils::EmailHash.compute(@test_email)
  'should_have_raised'
rescue Onetime::Problem => e
  e.message.include?('FEDERATION_SECRET')
rescue StandardError => e
  # Accept any error about missing secret
  e.message.include?('secret') || e.message.include?('HMAC') || e.message.include?('FEDERATION')
ensure
  # Restore the secret
  ENV['FEDERATION_SECRET'] = original_secret
end
#=> true

## Hashes are unique across large sample (collision resistance)
emails = 1000.times.map { |i| "user#{i}@example#{i % 100}.com" }
hashes = emails.map { |e| Onetime::Utils::EmailHash.compute(e) }
hashes.uniq.size == hashes.size
#=> true
