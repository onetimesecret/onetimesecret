# try/features/incoming/incoming_config_model_try.rb
#
# frozen_string_literal: true

# Tests for CustomDomain::IncomingConfig model (per-domain recipient storage).
#
# Review feedback coverage:
# 1. Email hashing consistency (lines 110, 124 in incoming_config.rb)
# 2. site.secret error handling: public_recipients raises, lookup returns nil
# 3. Recipient normalization in model layer
# 4. add_recipient raises vs remove_recipient returns boolean
# 5. MAX_RECIPIENTS edge cases
# 6. Duplicate email handling

require_relative '../../support/test_models'
OT.boot! :test, false

require 'onetime/models/custom_domain/incoming_config'

IncomingConfig = Onetime::CustomDomain::IncomingConfig

@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

# Setup: Create test customer, org, and domain for each test
@test_email = "incoming_model_#{@ts}_#{@entropy}@test.com"
@test_cust = Onetime::Customer.create!(email: @test_email)
@test_org = Onetime::Organization.create!("Incoming Model Test #{@ts}", @test_cust, "org_incoming_#{@ts}@test.com")
@test_domain = Onetime::CustomDomain.create!("incoming-model-#{@ts}-#{@entropy}.example.com", @test_org.objid)

# Store original site.secret for restoration
@original_site_secret = OT.conf.dig('site', 'secret')

# Helper to modify site.secret temporarily
def with_site_secret(value)
  original = OT.conf.dig('site', 'secret')
  if value.nil?
    OT.conf['site'].delete('secret')
  else
    OT.conf['site']['secret'] = value
  end
  yield
ensure
  if original.nil?
    OT.conf['site'].delete('secret')
  else
    OT.conf['site']['secret'] = original
  end
end

# --- EMAIL HASHING CONSISTENCY (Review Item 1) ---

## Hashing produces consistent output for same email
config = IncomingConfig.create!(domain_id: "hash_test_#{@ts}_1")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
hash1 = config.public_recipients.first[:hash]
hash2 = config.public_recipients.first[:hash]
config.destroy!
hash1 == hash2 && hash1.length == 64
#=> true

## Same email always produces the same hash (deterministic)
config = IncomingConfig.create!(domain_id: "hash_test_#{@ts}_2")
config.recipients = [{ email: 'alice@example.com', name: 'Alice' }]
config.save
first_call = config.public_recipients.first[:hash]
second_call = config.public_recipients.first[:hash]
config.destroy!
first_call == second_call
#=> true

## Hash lookup finds correct email by computed hash
config = IncomingConfig.create!(domain_id: "hash_test_#{@ts}_3")
config.recipients = [
  { email: 'bob@example.com', name: 'Bob' },
  { email: 'carol@example.com', name: 'Carol' }
]
config.save
bob_hash = config.public_recipients.find { |r| r[:name] == 'Bob' }[:hash]
found_email = config.lookup_recipient_email(bob_hash)
config.destroy!
found_email
#=> "bob@example.com"

## Hash from public_recipients matches hash used in lookup
config = IncomingConfig.create!(domain_id: "hash_test_#{@ts}_4")
config.recipients = [{ email: 'verify@example.com', name: 'Verify' }]
config.save
pub_hash = config.public_recipients.first[:hash]
lookup_result = config.lookup_recipient_email(pub_hash)
config.destroy!
lookup_result
#=> "verify@example.com"

# --- site.secret ERROR HANDLING (Review Item 2) ---

## public_recipients raises OT::Problem when site.secret is nil
config = IncomingConfig.create!(domain_id: "secret_test_#{@ts}_1")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
result = nil
begin
  with_site_secret(nil) do
    config.public_recipients
    result = 'did_not_raise'
  end
rescue OT::Problem => e
  result = e.message.include?('site.secret')
ensure
  config.destroy!
end
result
#=> true

## public_recipients does NOT raise for whitespace-only site.secret (edge case)
# Note: Current implementation uses .to_s.empty? which treats '   ' as non-empty.
# This test documents current behavior - whitespace secret is accepted (arguably a bug).
config = IncomingConfig.create!(domain_id: "secret_test_#{@ts}_2")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
result = nil
begin
  with_site_secret('   ') do
    config.public_recipients
    result = 'did_not_raise'
  end
rescue OT::Problem => e
  result = 'raised'
ensure
  config.destroy!
end
result
#=> "did_not_raise"

## lookup_recipient_email raises OT::Problem when site.secret is nil
# After fix: lookup_recipient_email now raises consistently with public_recipients
config = IncomingConfig.create!(domain_id: "secret_test_#{@ts}_3")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
result = nil
begin
  with_site_secret(nil) do
    config.lookup_recipient_email('any_hash')
    result = 'did_not_raise'
  end
rescue OT::Problem => e
  result = e.message.include?('site.secret')
ensure
  config.destroy!
end
result
#=> true

## lookup_recipient_email does NOT raise for whitespace-only site.secret (edge case)
# Note: Current implementation uses .to_s.empty? which treats '   ' as non-empty.
config = IncomingConfig.create!(domain_id: "secret_test_#{@ts}_4")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
result = nil
begin
  with_site_secret('   ') do
    result = config.lookup_recipient_email('any_hash')
  end
rescue OT::Problem
  result = 'raised'
ensure
  config.destroy!
end
result
#=> nil

## lookup_recipient_email returns nil for unknown hash (normal operation)
config = IncomingConfig.create!(domain_id: "secret_test_#{@ts}_5")
config.recipients = [{ email: 'test@example.com', name: 'Test' }]
config.save
result = config.lookup_recipient_email('nonexistent_hash_12345')
config.destroy!
result
#=> nil

# --- RECIPIENT NORMALIZATION (Review Item 3) ---

## Email normalization: strips whitespace
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_1")
config.recipients = [{ email: '  padded@example.com  ', name: 'Padded' }]
config.save
stored_email = config.recipients.first[:email]
config.destroy!
stored_email
#=> "padded@example.com"

## Email normalization: lowercases email
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_2")
config.recipients = [{ email: 'UPPER@EXAMPLE.COM', name: 'Upper' }]
config.save
stored_email = config.recipients.first[:email]
config.destroy!
stored_email
#=> "upper@example.com"

## Name normalization: strips whitespace
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_3")
config.recipients = [{ email: 'test@example.com', name: '  Spaced Name  ' }]
config.save
stored_name = config.recipients.first[:name]
config.destroy!
stored_name
#=> "Spaced Name"

## Name normalization: empty name defaults to email prefix
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_4")
config.recipients = [{ email: 'defaultname@example.com', name: '' }]
config.save
stored_name = config.recipients.first[:name]
config.destroy!
stored_name
#=> "defaultname"

## Empty email recipients are silently skipped
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_5")
config.recipients = [
  { email: '', name: 'Empty' },
  { email: 'valid@example.com', name: 'Valid' }
]
config.save
count = config.recipients.size
config.destroy!
count
#=> 1

## Whitespace-only email recipients are silently skipped
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_6")
config.recipients = [
  { email: '   ', name: 'Whitespace' },
  { email: 'real@example.com', name: 'Real' }
]
config.save
count = config.recipients.size
config.destroy!
count
#=> 1

## String keys and symbol keys both work
config = IncomingConfig.create!(domain_id: "normalize_#{@ts}_7")
config.recipients = [
  { 'email' => 'string@example.com', 'name' => 'String Keys' },
  { email: 'symbol@example.com', name: 'Symbol Keys' }
]
config.save
emails = config.recipients.map { |r| r[:email] }.sort
config.destroy!
emails
#=> ["string@example.com", "symbol@example.com"]

# --- add_recipient RAISES, remove_recipient RETURNS BOOLEAN (Review Item 4) ---

## add_recipient raises OT::Problem for duplicate email
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_1")
config.recipients = [{ email: 'existing@example.com', name: 'Existing' }]
config.save
result = nil
begin
  config.add_recipient(email: 'existing@example.com', name: 'Duplicate')
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('already exists')
ensure
  config.destroy!
end
result
#=> true

## add_recipient raises OT::Problem at max recipients
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_2")
max = IncomingConfig::MAX_RECIPIENTS
recipients = (1..max).map { |i| { email: "max#{i}@example.com", name: "Max #{i}" } }
config.recipients = recipients
config.save
result = nil
begin
  config.add_recipient(email: 'overflow@example.com', name: 'Overflow')
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?("Maximum #{max}")
ensure
  config.destroy!
end
result
#=> true

## add_recipient succeeds and saves
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_3")
config.add_recipient(email: 'new@example.com', name: 'New')
config.save
count = config.recipients.size
config.destroy!
count
#=> 1

## add_recipient normalizes email (strips, lowercases)
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_4")
config.add_recipient(email: '  UPPER@EXAMPLE.COM  ', name: 'Upper')
config.save
stored_email = config.recipients.first[:email]
config.destroy!
stored_email
#=> "upper@example.com"

## remove_recipient succeeds silently when email found (no return value)
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_5")
config.recipients = [{ email: 'toremove@example.com', name: 'To Remove' }]
config.save
config.remove_recipient(email: 'toremove@example.com')
remaining = config.recipients.size
config.destroy!
remaining
#=> 0

## remove_recipient raises OT::Problem when email not found
# After fix: remove_recipient now raises consistently with add_recipient
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_6")
config.recipients = [{ email: 'keep@example.com', name: 'Keep' }]
config.save
result = nil
begin
  config.remove_recipient(email: 'nonexistent@example.com')
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('not found')
ensure
  config.destroy!
end
result
#=> true

## remove_recipient is case-insensitive
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_7")
config.recipients = [{ email: 'lower@example.com', name: 'Lower' }]
config.save
config.remove_recipient(email: 'LOWER@EXAMPLE.COM')
remaining = config.recipients.size
config.destroy!
remaining
#=> 0

## remove_recipient handles whitespace in argument
config = IncomingConfig.create!(domain_id: "add_remove_#{@ts}_8")
config.recipients = [{ email: 'trimme@example.com', name: 'Trimme' }]
config.save
config.remove_recipient(email: '  trimme@example.com  ')
remaining = config.recipients.size
config.destroy!
remaining
#=> 0

# --- MAX_RECIPIENTS EDGE CASES (Review Item 5) ---

## MAX_RECIPIENTS constant is 20
IncomingConfig::MAX_RECIPIENTS
#=> 20

## Setting exactly MAX_RECIPIENTS succeeds
config = IncomingConfig.create!(domain_id: "max_#{@ts}_1")
max = IncomingConfig::MAX_RECIPIENTS
recipients = (1..max).map { |i| { email: "exact#{i}@example.com", name: "Exact #{i}" } }
config.recipients = recipients
config.save
count = config.recipients.size
config.destroy!
count
#=> 20

## Setting MAX_RECIPIENTS + 1 raises OT::Problem
config = IncomingConfig.create!(domain_id: "max_#{@ts}_2")
max = IncomingConfig::MAX_RECIPIENTS
recipients = (1..(max + 1)).map { |i| { email: "over#{i}@example.com", name: "Over #{i}" } }
result = nil
begin
  config.recipients = recipients
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?("Maximum #{max}")
ensure
  config.destroy!
end
result
#=> true

# --- DUPLICATE EMAIL HANDLING (Review Item 6) ---

## Duplicate emails in recipients= raises OT::Problem
config = IncomingConfig.create!(domain_id: "dup_#{@ts}_1")
result = nil
begin
  config.recipients = [
    { email: 'same@example.com', name: 'First' },
    { email: 'same@example.com', name: 'Second' }
  ]
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('Duplicate')
ensure
  config.destroy!
end
result
#=> true

## Duplicate detection is case-insensitive
config = IncomingConfig.create!(domain_id: "dup_#{@ts}_2")
result = nil
begin
  config.recipients = [
    { email: 'lower@example.com', name: 'Lower' },
    { email: 'LOWER@EXAMPLE.COM', name: 'Upper' }
  ]
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('Duplicate')
ensure
  config.destroy!
end
result
#=> true

# --- EMAIL FORMAT VALIDATION ---

## Invalid email format raises OT::Problem
config = IncomingConfig.create!(domain_id: "format_#{@ts}_1")
result = nil
begin
  config.recipients = [{ email: 'not-an-email', name: 'Invalid' }]
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('Invalid email')
ensure
  config.destroy!
end
result
#=> true

## Email without domain raises OT::Problem
config = IncomingConfig.create!(domain_id: "format_#{@ts}_2")
result = nil
begin
  config.recipients = [{ email: 'nodomain@', name: 'No Domain' }]
  result = 'did_not_raise'
rescue OT::Problem => e
  result = e.message.include?('Invalid email')
ensure
  config.destroy!
end
result
#=> true

# --- ENABLED/DISABLED STATE ---

## New config defaults to disabled
config = IncomingConfig.create!(domain_id: "state_#{@ts}_1")
result = config.enabled?
config.destroy!
result
#=> false

## enable! sets enabled to true and saves
config = IncomingConfig.create!(domain_id: "state_#{@ts}_2")
config.enable!
result = config.enabled?
config.destroy!
result
#=> true

## disable! sets enabled to false and saves
config = IncomingConfig.create!(domain_id: "state_#{@ts}_3")
config.enable!
config.disable!
result = config.enabled?
config.destroy!
result
#=> false

# --- CLEAR RECIPIENTS ---

## clear_recipients! removes all recipients
config = IncomingConfig.create!(domain_id: "clear_#{@ts}_1")
config.recipients = [
  { email: 'one@example.com', name: 'One' },
  { email: 'two@example.com', name: 'Two' }
]
config.save
config.clear_recipients!
count = config.recipients.size
config.destroy!
count
#=> 0

# --- JSON PARSE RESILIENCE ---

## Empty recipients_json returns empty array
config = IncomingConfig.create!(domain_id: "json_#{@ts}_1")
config.recipients_json = ''
config.save
result = config.recipients
config.destroy!
result
#=> []

## Malformed JSON returns empty array (no crash)
config = IncomingConfig.create!(domain_id: "json_#{@ts}_2")
config.recipients_json = 'not valid json {'
config.save
result = config.recipients
config.destroy!
result
#=> []

# --- TEARDOWN ---

## Cleanup test fixtures
begin
  @test_domain.destroy! rescue nil
  @test_org.destroy! rescue nil
  @test_cust.destroy! rescue nil
  true
rescue => e
  "cleanup_error: #{e.class}"
end
#=> true
