# try/features/incoming/recipient_resolver_try.rb
#
# frozen_string_literal: true

# Tests for RecipientResolver domain-aware recipient resolution.
#
# Key coverage:
# 1. Canonical domain resolution (boot-time config)
# 2. Custom domain resolution (per-domain Redis config)
# 3. Orphaned domain handling (custom domain with no resolvable owner org)
# 4. Entitlement checks via require_domain_entitlement!

require_relative '../../support/test_models'
OT.boot! :test, false

# Load the RecipientResolver directly using relative path
require_relative '../../../lib/onetime/incoming/recipient_resolver'

# Setup: Create unique test identifiers
@ts = Familia.now.to_i
@entropy = SecureRandom.hex(4)

## RecipientResolver exists
defined?(Onetime::Incoming::RecipientResolver)
#=> "constant"

## Canonical domain enabled? uses boot-time config
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.enabled?.class
#=> FalseClass

## Canonical domain public_recipients returns global list
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.public_recipients.class
#=> Array

## Canonical domain lookup delegates to global lookup
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.lookup('nonexistent_hash')
#=> nil

## Nil domain_strategy treated as canonical
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: nil)
resolver.public_recipients.class
#=> Array

## Custom domain without display_domain returns empty recipients
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :custom, display_domain: nil)
resolver.public_recipients
#=> []

## Custom domain with nonexistent domain returns false for enabled?
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :custom, display_domain: "nonexistent-#{@ts}.example.com")
resolver.enabled?
#=> false

## Custom domain lookup with nonexistent domain returns nil
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :custom, display_domain: "nonexistent-#{@ts}.example.com")
resolver.lookup('some_hash')
#=> nil

## Unknown domain_strategy returns empty recipients
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :unknown_strategy)
resolver.public_recipients
#=> []

## Unknown domain_strategy returns false for enabled?
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :unknown_strategy)
resolver.enabled?
#=> false

## Unknown domain_strategy lookup returns nil
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :unknown_strategy)
resolver.lookup('any_hash')
#=> nil

## require_domain_entitlement! returns true for canonical domain (no-op)
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.require_domain_entitlement!('incoming_secrets')
#=> true

## require_domain_entitlement! returns true for nil domain_strategy
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: nil)
resolver.require_domain_entitlement!('incoming_secrets')
#=> true

## ORPHANED DOMAIN: require_domain_entitlement! raises Forbidden for custom domain with no owner
# Create a custom domain record with an invalid org_id that won't resolve
@orphan_domain_display = "orphan-#{@ts}-#{@entropy}.example.com"
@orphan_org_id = "nonexistent_org_#{@ts}"

# Create domain manually without a valid org
@orphan_domain = Onetime::CustomDomain.new
@orphan_domain.display_domain = @orphan_domain_display
@orphan_domain.org_id = @orphan_org_id
@orphan_domain.created = OT.now.to_i
@orphan_domain.updated = OT.now.to_i
@orphan_domain.save

# Register in display_domains lookup
Onetime::CustomDomain.display_domains.put(@orphan_domain_display, @orphan_domain.identifier)

begin
  resolver = Onetime::Incoming::RecipientResolver.new(
    domain_strategy: :custom,
    display_domain: @orphan_domain_display
  )
  resolver.require_domain_entitlement!('incoming_secrets')
  'did_not_raise'
rescue OT::Forbidden => e
  e.message
ensure
  # Cleanup orphan domain
  Onetime::CustomDomain.display_domains.remove(@orphan_domain_display)
  @orphan_domain.destroy! rescue nil
end
#=> "Custom domain organization could not be resolved"

## config_data returns hash with expected keys for canonical domain
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
data = resolver.config_data
[data.key?(:enabled), data.key?(:memo_max_length), data.key?(:default_ttl), data.key?(:recipients)]
#=> [true, true, true, true]

## config_data for canonical domain returns default memo_max_length
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.config_data[:memo_max_length]
#=> 50

## config_data for canonical domain returns default ttl
resolver = Onetime::Incoming::RecipientResolver.new(domain_strategy: :canonical)
resolver.config_data[:default_ttl]
#=> 604800

## CUSTOM DOMAIN WITH ORG: Setup for valid custom domain tests
@test_user = Onetime::Customer.create!(email: "resolver_test_#{@ts}_#{@entropy}@test.com")
@test_org = Onetime::Organization.create!("Resolver Test Org #{@ts}", @test_user, "resolver_org_#{@ts}@test.com")
@test_domain_display = "resolver-test-#{@ts}-#{@entropy}.example.com"
@test_domain = Onetime::CustomDomain.create!(@test_domain_display, @test_org.objid)
@test_domain.exists?
#=> true

## Custom domain enabled? returns false when no recipients configured
resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
resolver.enabled?
#=> false

## Custom domain with recipients becomes enabled
# Add recipients to the domain config
config = @test_domain.incoming_secrets_config
config.set_incoming_recipients([
  { 'email' => 'support@example.com', 'name' => 'Support' },
  { 'email' => 'admin@example.com', 'name' => 'Admin' }
])
@test_domain.update_incoming_secrets_config(config)

resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
resolver.enabled?
#=> true

## Custom domain public_recipients returns hashed list
resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
recipients = resolver.public_recipients
[recipients.size, recipients.first.keys.sort]
#=> [2, ["digest", "display_name"]]

## Custom domain lookup resolves hash to email
site_secret = OT.conf.dig('site', 'secret')
expected_hash = Digest::SHA256.hexdigest("support@example.com:#{site_secret}")

resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
resolver.lookup(expected_hash)
#=> "support@example.com"

## Custom domain lookup returns nil for unknown hash
resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
resolver.lookup('invalid_hash_value')
#=> nil

## Custom domain config_data returns domain-specific values
resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
data = resolver.config_data
[data[:enabled], data[:recipients].size]
#=> [true, 2]

## require_domain_entitlement! with valid org and entitlement returns true
# By default in tests, billing is disabled so all entitlements are granted
resolver = Onetime::Incoming::RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: @test_domain_display
)
resolver.require_domain_entitlement!('incoming_secrets')
#=> true

## Teardown: Clean up test data
begin
  @test_domain.destroy!
  @test_org.destroy!
  @test_user.destroy!
  true
rescue => e
  "cleanup_error: #{e.class}"
end
#=> true
