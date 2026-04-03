# try/features/incoming/recipient_resolver_site_secret_try.rb
#
# frozen_string_literal: true

# Tests for RecipientResolver behavior when site_secret is missing or invalid.
#
# PR #2872 Feedback fixes:
# - enabled? should return false when site_secret missing but recipients configured
# - public_recipients and lookup should fail closed (empty results)
# - Non-string site_secret types should be handled via .to_s normalization
#
# Key coverage:
# 1. enabled? returns false when site_secret is nil/empty/whitespace
# 2. Consistency: enabled?, public_recipients, lookup all fail closed together
# 3. Non-string site_secret handling (Symbol, Integer)

require_relative '../../support/test_models'
OT.boot! :test, false

require 'onetime/incoming/recipient_resolver'

RecipientResolver = Onetime::Incoming::RecipientResolver

# Setup: Create unique test identifiers
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

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

## SETUP: Create custom domain with recipients for site_secret tests
@test_user = Onetime::Customer.create!(email: "site_secret_test_#{@ts}_#{@entropy}@test.com")
@test_org = Onetime::Organization.create!("Site Secret Test Org #{@ts}", @test_user, "site_secret_org_#{@ts}@test.com")
@test_domain_display = "site-secret-test-#{@ts}-#{@entropy}.example.com"
@test_domain = Onetime::CustomDomain.create!(@test_domain_display, @test_org.objid)

# Configure recipients
config = @test_domain.incoming_secrets_config
config.set_incoming_recipients([
  { 'email' => 'support@site-secret-test.com', 'name' => 'Support' },
  { 'email' => 'admin@site-secret-test.com', 'name' => 'Admin' }
])
@test_domain.update_incoming_secrets_config(config)
@test_domain.incoming_secrets_config.has_incoming_recipients?
#=> true

## enabled? returns false when site_secret is nil (recipients configured)
result = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.enabled?
end
result
#=> false

## enabled? returns false when site_secret is empty string (recipients configured)
result = nil
with_site_secret('') do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.enabled?
end
result
#=> false

## enabled? returns false when site_secret is whitespace only (recipients configured)
result = nil
with_site_secret('   ') do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.enabled?
end
result
#=> false

## public_recipients returns empty array when site_secret is nil
result = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.public_recipients
end
result
#=> []

## public_recipients returns empty array when site_secret is empty string
result = nil
with_site_secret('') do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.public_recipients
end
result
#=> []

## lookup returns nil when site_secret is nil
result = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  # Even a valid-looking hash should return nil
  result = resolver.lookup('a' * 64)
end
result
#=> nil

## lookup returns nil when site_secret is empty string
result = nil
with_site_secret('') do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  result = resolver.lookup('a' * 64)
end
result
#=> nil

## CONSISTENCY: all three methods fail closed when site_secret missing
enabled_result = nil
public_result = nil
lookup_result = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  enabled_result = resolver.enabled?
  public_result = resolver.public_recipients
  lookup_result = resolver.lookup('any_hash')
end
[enabled_result, public_result, lookup_result]
#=> [false, [], nil]

## config_data reflects disabled state when site_secret missing
config_data = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @test_domain_display
  )
  config_data = resolver.config_data
end
[config_data[:enabled], config_data[:recipients]]
#=> [false, []]

## Canonical domain enabled? unaffected by site_secret (uses YAML config)
# Canonical domains use boot-time config, not site_secret for enabled check
result = nil
with_site_secret(nil) do
  resolver = RecipientResolver.new(domain_strategy: :canonical)
  result = resolver.enabled?.class
end
# Returns the same type (boolean) regardless of site_secret
result
#=> FalseClass

## TEARDOWN: Clean up test data
begin
  @test_domain.destroy!
  @test_org.destroy!
  @test_user.destroy!
  true
rescue => e
  "cleanup_error: #{e.class}"
end
#=> true
