# try/unit/api/v2/secrets/validate_domain_verification_try.rb
#
# frozen_string_literal: true

# Tests for V2::Logic::Secrets::BaseSecretAction#validate_domain_verification.
#
# Behavior gated by features.domains.require_verified:
# - When the toggle is off (default), unverified custom share_domains are
#   accepted (preserves pre-fix behavior).
# - When the toggle is on, secret creation against an unverified custom
#   share_domain raises Onetime::FormError. This applies to owners too —
#   the verification check is about domain state, not authorization.
# - Verified domains are always allowed regardless of the toggle.
# - Canonical domains are filtered out earlier in process_share_domain
#   (default_domain?), so the verification check never runs for them.

require_relative '../../../../support/test_helpers'

OT.boot! :test, false

require 'v2/logic'

@timestamp = Familia.now.to_i

@owner_email = generate_unique_test_email("verif_owner")
@owner = Onetime::Customer.create!(email: @owner_email)
@org   = Onetime::Organization.create!("DomainVerif Org #{@timestamp}", @owner, "orgverif_#{@timestamp}@test.com")
@domain = Onetime::CustomDomain.create!("verif-#{@timestamp}.example.com", @org.objid)

# Build a logic instance the same way validate_domain_permissions_try does.
def create_test_logic(customer, share_domain_value: nil, domain_strategy: nil, display_domain: nil)
  sess = MockSession.new
  metadata = {}
  metadata[:domain_strategy] = domain_strategy if domain_strategy
  metadata[:display_domain]  = display_domain  if display_domain
  auth_method = customer.nil? ? 'anonymous' : 'basic'
  strategy_result = MockStrategyResult.new(session: sess, user: customer, auth_method: auth_method, metadata: metadata)
  params = {
    'secret' => {
      'secret' => 'test secret',
      'ttl' => '3600',
      'share_domain' => share_domain_value
    }
  }
  V2::Logic::Secrets::ConcealSecret.new(strategy_result, params, 'en')
end

# Mutate the require_verified flag in-process. Config is frozen outside of
# test mode; OT.boot! :test, false leaves it mutable for tryouts.
def set_require_verified(value)
  OT.conf['features'] ||= {}
  OT.conf['features']['domains'] ||= {}
  OT.conf['features']['domains']['require_verified'] = value
end

@original_require_verified = OT.conf.dig('features', 'domains', 'require_verified')

## Toggle off + unverified domain: owner is allowed (default behavior unchanged)
set_require_verified(false)
@domain.verified = 'false'
@domain.save
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

## Toggle on + unverified domain: owner is rejected
set_require_verified(true)
@domain.verified = 'false'
@domain.save
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=~> /Custom domain is not verified:/

## Toggle on + unverified domain: error message includes the domain name
set_require_verified(true)
@domain.verified = 'false'
@domain.save
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message.include?('verif-')
end
#=> true

## Toggle on + verified domain: owner is allowed
set_require_verified(true)
@domain.verified = 'true'
@domain.save
logic = create_test_logic(@owner, share_domain_value: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

## Toggle on + verified domain on custom-domain context: allowed
set_require_verified(true)
@domain.verified = 'true'
@domain.save
logic = create_test_logic(@owner,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=> :success

## Toggle on + unverified domain on custom-domain context: rejected
set_require_verified(true)
@domain.verified = 'false'
@domain.save
logic = create_test_logic(@owner,
  share_domain_value: @domain.display_domain,
  domain_strategy: :custom,
  display_domain: @domain.display_domain)
begin
  logic.send(:validate_domain_access, @domain.display_domain)
  :success
rescue Onetime::FormError => e
  e.message
end
#=~> /Custom domain is not verified:/

# Teardown
set_require_verified(@original_require_verified)
@domain.destroy!
@org.destroy!
@owner.destroy!
