# try/unit/config/config_serializer_omniauth_try.rb
#
# Tests for ConfigSerializer.build_omniauth_config method.
# Verifies the serialization of OmniAuth feature configuration for frontend consumption.
#
# frozen_string_literal: true

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
# Must also set mode to 'full' so omniauth_enabled? returns true (since it checks full_enabled?)
def with_omniauth_config(enabled:, display_name: '')
  config = Onetime.auth_config.instance_variable_get(:@config)
  original_mode = config['mode']
  config['mode'] = 'full'

  features = config['full']['features']
  original_omniauth = features['omniauth']
  original_provider = features['sso_display_name']

  features['omniauth'] = enabled
  features['sso_display_name'] = display_name
  yield
ensure
  config['mode'] = original_mode
  features['omniauth'] = original_omniauth
  features['sso_display_name'] = original_provider
end

## build_omniauth_config returns false when omniauth is disabled
with_omniauth_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
#=> false

## build_omniauth_config returns hash with enabled true when omniauth is enabled
result = with_omniauth_config(enabled: true) do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result['enabled']
#=> true

## build_omniauth_config omits display_name when not configured
result = with_omniauth_config(enabled: true, display_name: '') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result.key?('display_name')
#=> false

## build_omniauth_config omits display_name when whitespace-only
result = with_omniauth_config(enabled: true, display_name: '   ') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result.key?('display_name')
#=> false

## build_omniauth_config includes display_name when configured
result = with_omniauth_config(enabled: true, display_name: 'Zitadel') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result['display_name']
#=> "Zitadel"

## build_omniauth_config returns correct structure with provider name
result = with_omniauth_config(enabled: true, display_name: 'Okta') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
[result['enabled'], result['display_name']]
#=> [true, "Okta"]

## build_feature_flags includes omniauth as false when disabled
result = with_omniauth_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_feature_flags)
end
result['omniauth']
#=> false

## build_feature_flags includes omniauth hash when enabled
result = with_omniauth_config(enabled: true, display_name: 'Azure AD') do
  Core::Views::ConfigSerializer.send(:build_feature_flags)
end
[result['omniauth']['enabled'], result['omniauth']['display_name']]
#=> [true, "Azure AD"]

## build_omniauth_config includes provider_name for backwards compatibility
result = with_omniauth_config(enabled: true, display_name: 'Okta') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result['provider_name']
#=> "Okta"

## build_omniauth_config sends both display_name and provider_name with same value
result = with_omniauth_config(enabled: true, display_name: 'Zitadel') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
[result['display_name'], result['provider_name']]
#=> ["Zitadel", "Zitadel"]
