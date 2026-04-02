# try/unit/config/config_serializer_sso_try.rb
#
# frozen_string_literal: true

# Tests for ConfigSerializer.build_sso_config method.
# Verifies the serialization of SSO feature configuration for frontend consumption.

ENV['AUTHENTICATION_MODE'] = 'full'

require 'rack/request'
require 'rack/mock'

require_relative '../../support/test_helpers'

require 'onetime'
require_relative '../../../apps/web/core/views'

OT.boot! :test, false

# Store original features for restoration
@original_features = Onetime.auth_config.features.dup

# Helper to modify features temporarily
# Must also set mode to 'full' so sso_enabled? returns true (since it checks full_enabled?)
# Sets OIDC env vars so sso_providers returns at least one provider entry.
def with_sso_config(enabled:, display_name: '')
  config = Onetime.auth_config.instance_variable_get(:@config)
  original_mode = config['mode']
  config['mode'] = 'full'

  features = config['full']['features']
  original_sso = features['sso']

  # Ensure sso config section exists
  config['full']['sso'] ||= {}
  sso_section = config['full']['sso']
  original_display = sso_section['sso_display_name']

  # Set OIDC env vars so sso_providers builds a provider entry
  original_issuer = ENV['OIDC_ISSUER']
  original_client = ENV['OIDC_CLIENT_ID']
  original_oidc_display = ENV['OIDC_DISPLAY_NAME']
  ENV['OIDC_ISSUER'] = 'https://test.example.com'
  ENV['OIDC_CLIENT_ID'] = 'test-client-id'
  ENV.delete('OIDC_DISPLAY_NAME') # let sso_display_name fallback work

  features['sso'] = enabled
  sso_section['sso_display_name'] = display_name
  yield
ensure
  config['mode'] = original_mode
  features['sso'] = original_sso
  sso_section['sso_display_name'] = original_display
  ENV['OIDC_ISSUER'] = original_issuer
  ENV['OIDC_CLIENT_ID'] = original_client
  ENV['OIDC_DISPLAY_NAME'] = original_oidc_display
end

# Helper to modify organizations feature flags temporarily
# Defined in setup section to be available for all test cases
def with_orgs_sso_enabled(enabled:, orgs_enabled: false)
  config = Onetime.auth_config.instance_variable_get(:@config)
  features = config['full']['features'] ||= {}
  original_orgs = features['organizations']

  features['organizations'] = {
    'enabled' => orgs_enabled,
    'sso_enabled' => enabled,
  }
  yield
ensure
  if original_orgs.nil?
    features.delete('organizations')
  else
    features['organizations'] = original_orgs
  end
end

## build_sso_config returns false when SSO is disabled
result = with_sso_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result
#=> false

## build_sso_config returns hash with enabled true when SSO is enabled
result = with_sso_config(enabled: true) do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result['enabled']
#=> true

## build_sso_config omits display_name when not configured
result = with_sso_config(enabled: true, display_name: '') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result.key?('display_name')
#=> false

## build_sso_config omits display_name when whitespace-only
result = with_sso_config(enabled: true, display_name: '   ') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result.key?('display_name')
#=> false

## build_sso_config includes display_name in provider entry when configured
result = with_sso_config(enabled: true, display_name: 'Zitadel') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result['providers'].first['display_name']
#=> "Zitadel"

## build_sso_config returns correct structure with provider display_name
result = with_sso_config(enabled: true, display_name: 'Okta') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
[result['enabled'], result['providers'].first['display_name']]
#=> [true, "Okta"]

## build_feature_flags includes sso as false when disabled
result = with_sso_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_feature_flags, {})
end
result['sso']
#=> false

## build_feature_flags includes sso hash when enabled
result = with_sso_config(enabled: true, display_name: 'Azure AD') do
  Core::Views::ConfigSerializer.send(:build_feature_flags, {})
end
[result['sso']['enabled'], result['sso']['providers'].first['display_name']]
#=> [true, "Azure AD"]

## build_feature_flags includes restrict_to key
result = with_sso_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_feature_flags, {})
end
result.key?('restrict_to')
#=> true

## build_sso_config provider entry includes route_name
result = with_sso_config(enabled: true, display_name: 'Okta') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result['providers'].first['route_name']
#=> "oidc"

## build_sso_config provider entry has both route_name and display_name
result = with_sso_config(enabled: true, display_name: 'Zitadel') do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
[result['providers'].first['route_name'], result['providers'].first['display_name']]
#=> ["oidc", "Zitadel"]

## sso_providers returns string-keyed hashes (contract with ConfigSerializer)
with_sso_config(enabled: true) do
  providers = Onetime.auth_config.sso_providers
  providers.empty? || providers.all? { |p| p.keys.all? { |k| k.is_a?(String) } }
end
#=> true

## build_sso_config providers array has route_name and display_name strings
result = with_sso_config(enabled: true) do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result['providers'].is_a?(Array)
#=> true

## build_sso_config provider entries use string keys
result = with_sso_config(enabled: true) do
  Core::Views::ConfigSerializer.send(:build_sso_config, {})
end
result['providers'].empty? || result['providers'].all? { |p| p.key?('route_name') && p.key?('display_name') }
#=> true

## ConfigSerializer reads sso_providers with string keys not symbol keys
# This validates the contract: sso_providers returns {'route_name' => ...}
# and build_sso_config accesses p['route_name'], not p[:route_name]
with_sso_config(enabled: true) do
  providers = Onetime.auth_config.sso_providers
  next true if providers.empty?

  # Verify string-key access returns non-nil values
  providers.all? { |p| !p['route_name'].nil? && !p['display_name'].nil? }
end
#=> true

## build_feature_flags includes organizations.sso_enabled as false when disabled
result = with_orgs_sso_enabled(enabled: false) do
  config = Onetime.auth_config.instance_variable_get(:@config)
  view_vars = { 'features' => config['full']['features'] }
  Core::Views::ConfigSerializer.send(:build_feature_flags, view_vars)
end
result['organizations']['sso_enabled']
#=> false

## build_feature_flags includes organizations.sso_enabled as true when enabled
result = with_orgs_sso_enabled(enabled: true) do
  config = Onetime.auth_config.instance_variable_get(:@config)
  view_vars = { 'features' => config['full']['features'] }
  Core::Views::ConfigSerializer.send(:build_feature_flags, view_vars)
end
result['organizations']['sso_enabled']
#=> true

## build_feature_flags includes organizations.enabled alongside sso_enabled
result = with_orgs_sso_enabled(enabled: true, orgs_enabled: true) do
  config = Onetime.auth_config.instance_variable_get(:@config)
  view_vars = { 'features' => config['full']['features'] }
  Core::Views::ConfigSerializer.send(:build_feature_flags, view_vars)
end
[result['organizations']['enabled'], result['organizations']['sso_enabled']]
#=> [true, true]

## build_feature_flags organizations defaults to false when features is empty
result = Core::Views::ConfigSerializer.send(:build_feature_flags, {})
[result['organizations']['enabled'], result['organizations']['sso_enabled']]
#=> [false, false]

## build_feature_flags organizations defaults to false when organizations key missing
result = Core::Views::ConfigSerializer.send(:build_feature_flags, { 'features' => {} })
[result['organizations']['enabled'], result['organizations']['sso_enabled']]
#=> [false, false]

## build_feature_flags organizations.sso_enabled is independent of organizations.enabled
result = with_orgs_sso_enabled(enabled: true, orgs_enabled: false) do
  config = Onetime.auth_config.instance_variable_get(:@config)
  view_vars = { 'features' => config['full']['features'] }
  Core::Views::ConfigSerializer.send(:build_feature_flags, view_vars)
end
[result['organizations']['enabled'], result['organizations']['sso_enabled']]
#=> [false, true]
