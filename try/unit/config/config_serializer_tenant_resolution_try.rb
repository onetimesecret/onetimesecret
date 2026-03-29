# try/unit/config/config_serializer_tenant_resolution_try.rb
#
# frozen_string_literal: true

# Tests for ConfigSerializer tenant resolution path in build_sso_config.
# Verifies domain-aware SSO provider resolution for custom domains vs
# canonical domains.
#
# Issue: #2786 - Per-domain SSO configuration

ENV['AUTHENTICATION_MODE'] = 'full'

require 'rack/request'
require 'rack/mock'

require_relative '../../support/test_helpers'

require 'onetime'
require_relative '../../../apps/web/core/views'

OT.boot! :test, false

# Familia encryption for DomainSsoConfig
key_v1 = 'test_encryption_key_32bytes_ok!!'
key_v2 = 'another_test_key_for_testing_!!'

Familia.configure do |config|
  config.encryption_keys = {
    v1: Base64.strict_encode64(key_v1),
    v2: Base64.strict_encode64(key_v2),
  }
  config.current_key_version = :v1
  config.encryption_personalization = 'ConfigSerializerTenantTest'
end

@original_features = Onetime.auth_config.features.dup

# Store original fallback setting for restoration
@original_sso_config = OT.conf.dig('site', 'sso')&.dup

# Helper to set fallback config
def with_fallback_config(allow)
  OT.conf['site'] ||= {}
  OT.conf['site']['sso'] ||= {}
  OT.conf['site']['sso']['allow_platform_fallback_for_tenants'] = allow
end

# Helper to restore fallback config
def restore_fallback_config
  if @original_sso_config
    OT.conf['site']['sso'] = @original_sso_config.dup
  else
    OT.conf['site']&.delete('sso')
  end
end

# Helper to enable SSO at platform level with env vars
def with_sso_platform_enabled
  config = Onetime.auth_config.instance_variable_get(:@config)
  original_mode = config['mode']
  config['mode'] = 'full'

  features = config['full']['features']
  original_sso = features['sso']

  original_issuer = ENV['OIDC_ISSUER']
  original_client = ENV['OIDC_CLIENT_ID']
  ENV['OIDC_ISSUER'] = 'https://test.example.com'
  ENV['OIDC_CLIENT_ID'] = 'test-client-id'

  features['sso'] = true
  yield
ensure
  config['mode'] = original_mode
  features['sso'] = original_sso
  ENV['OIDC_ISSUER'] = original_issuer
  ENV['OIDC_CLIENT_ID'] = original_client
end

# Create a test CustomDomain + DomainSsoConfig for tenant resolution tests.
# Returns [custom_domain, sso_config] for use in assertions.
@test_run_id = "try-#{SecureRandom.hex(4)}"
@test_display_domain = "secrets-#{@test_run_id}.tenant-test.example.com"

# Create customer/org/domain/sso_config fixtures
@test_owner = Onetime::Customer.new(email: "owner-#{@test_run_id}@try-test.local")
@test_owner.save

@test_org = Onetime::Organization.create!(
  "Try Test Org #{@test_run_id}",
  @test_owner,
  "contact-#{@test_run_id}@try-test.local"
)

@test_custom_domain = Onetime::CustomDomain.new(
  display_domain: @test_display_domain,
  org_id: @test_org.org_id
)
@test_custom_domain.save
Onetime::CustomDomain.display_domains.put(@test_display_domain, @test_custom_domain.domainid)

@test_sso_config = Onetime::DomainSsoConfig.create!(
  domain_id: @test_custom_domain.identifier,
  org_id: @test_org.org_id,
  provider_type: 'entra_id',
  display_name: 'Try Test Entra ID',
  tenant_id: "tenant-#{@test_run_id}",
  client_id: "client-#{@test_run_id}",
  client_secret: "secret-#{@test_run_id}",
  enabled: true
)

# Domain without SSO config (for fallback tests)
@no_sso_display_domain = "secrets-nosso-#{@test_run_id}.tenant-test.example.com"
@no_sso_custom_domain = Onetime::CustomDomain.new(
  display_domain: @no_sso_display_domain,
  org_id: @test_org.org_id
)
@no_sso_custom_domain.save
Onetime::CustomDomain.display_domains.put(@no_sso_display_domain, @no_sso_custom_domain.domainid)

## Request from custom domain WITH DomainSsoConfig returns tenant provider
result = with_sso_platform_enabled do
  view_vars = {
    'display_domain' => @test_display_domain,
    'domain_strategy' => :custom,
  }
  Core::Views::ConfigSerializer.send(:build_sso_config, view_vars)
end
[result['enabled'], result['providers'].length, result['providers'].first['display_name']]
#=> [true, 1, "Try Test Entra ID"]

## Tenant provider route_name matches the provider_type from DomainSsoConfig
result = with_sso_platform_enabled do
  view_vars = {
    'display_domain' => @test_display_domain,
    'domain_strategy' => :custom,
  }
  Core::Views::ConfigSerializer.send(:build_sso_config, view_vars)
end
result['providers'].first['route_name']
#=> "entra_id"

## Request from custom domain WITHOUT DomainSsoConfig, fallback allowed returns platform providers
result = with_sso_platform_enabled do
  with_fallback_config(true)
  view_vars = {
    'display_domain' => @no_sso_display_domain,
    'domain_strategy' => :custom,
  }
  sso = Core::Views::ConfigSerializer.send(:build_sso_config, view_vars)
  restore_fallback_config
  sso
end
result['enabled']
#=> true

## Request from custom domain WITHOUT DomainSsoConfig, fallback disallowed returns empty providers
result = with_sso_platform_enabled do
  with_fallback_config(false)
  view_vars = {
    'display_domain' => @no_sso_display_domain,
    'domain_strategy' => :custom,
  }
  sso = Core::Views::ConfigSerializer.send(:build_sso_config, view_vars)
  restore_fallback_config
  sso
end
[result['enabled'], result['providers']]
#=> [false, []]

## Request from canonical domain returns platform providers (skips tenant resolution)
result = with_sso_platform_enabled do
  view_vars = {
    'display_domain' => '',
    'domain_strategy' => :canonical,
  }
  Core::Views::ConfigSerializer.send(:build_sso_config, view_vars)
end
result['enabled']
#=> true

## Request from canonical domain does not attempt tenant resolution
result = with_sso_platform_enabled do
  view_vars = {
    'display_domain' => '',
    'domain_strategy' => :canonical,
  }
  # resolve_tenant_sso_config should return nil for empty display_domain
  Core::Views::ConfigSerializer.send(:resolve_tenant_sso_config, view_vars)
end
result
#=> nil

## tenant_domain? returns true when domain_strategy is :custom
Core::Views::ConfigSerializer.send(:tenant_domain?, { 'domain_strategy' => :custom })
#=> true

## tenant_domain? returns false when domain_strategy is :canonical
Core::Views::ConfigSerializer.send(:tenant_domain?, { 'domain_strategy' => :canonical })
#=> false

## tenant_domain? returns false when domain_strategy is :subdomain
Core::Views::ConfigSerializer.send(:tenant_domain?, { 'domain_strategy' => :subdomain })
#=> false

## tenant_domain? returns false when domain_strategy is nil
Core::Views::ConfigSerializer.send(:tenant_domain?, { 'domain_strategy' => nil })
#=> false

## tenant_domain? returns false when domain_strategy key is missing
Core::Views::ConfigSerializer.send(:tenant_domain?, {})
#=> false

## allow_platform_fallback? returns true when config is true
with_fallback_config(true)
result = Core::Views::ConfigSerializer.send(:allow_platform_fallback?)
restore_fallback_config
result
#=> true

## allow_platform_fallback? returns false when config is false
with_fallback_config(false)
result = Core::Views::ConfigSerializer.send(:allow_platform_fallback?)
restore_fallback_config
result
#=> false

## allow_platform_fallback? defaults to true when config is nil
with_fallback_config(nil)
result = Core::Views::ConfigSerializer.send(:allow_platform_fallback?)
restore_fallback_config
result
#=> true

# Teardown: clean up Valkey fixtures
Onetime::DomainSsoConfig.delete_for_domain!(@test_custom_domain.identifier) rescue nil
Onetime::CustomDomain.display_domains.remove(@test_display_domain) rescue nil
Onetime::CustomDomain.display_domains.remove(@no_sso_display_domain) rescue nil
@test_custom_domain&.destroy! rescue nil
@no_sso_custom_domain&.destroy! rescue nil
@test_org&.destroy! rescue nil
