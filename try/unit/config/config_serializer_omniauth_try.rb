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
def with_omniauth_config(enabled:, provider_name: '')
  features = Onetime.auth_config.instance_variable_get(:@config)['full']['features']
  features['omniauth'] = enabled
  features['omniauth_provider_name'] = provider_name
  yield
ensure
  features['omniauth'] = false
  features['omniauth_provider_name'] = ''
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

## build_omniauth_config omits provider_name when not configured
result = with_omniauth_config(enabled: true, provider_name: '') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result.key?('provider_name')
#=> false

## build_omniauth_config omits provider_name when whitespace-only
result = with_omniauth_config(enabled: true, provider_name: '   ') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result.key?('provider_name')
#=> false

## build_omniauth_config includes provider_name when configured
result = with_omniauth_config(enabled: true, provider_name: 'Zitadel') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
result['provider_name']
#=> "Zitadel"

## build_omniauth_config returns correct structure with provider name
result = with_omniauth_config(enabled: true, provider_name: 'Okta') do
  Core::Views::ConfigSerializer.send(:build_omniauth_config)
end
[result['enabled'], result['provider_name']]
#=> [true, "Okta"]

## build_feature_flags includes omniauth as false when disabled
result = with_omniauth_config(enabled: false) do
  Core::Views::ConfigSerializer.send(:build_feature_flags)
end
result['omniauth']
#=> false

## build_feature_flags includes omniauth hash when enabled
result = with_omniauth_config(enabled: true, provider_name: 'Azure AD') do
  Core::Views::ConfigSerializer.send(:build_feature_flags)
end
[result['omniauth']['enabled'], result['omniauth']['provider_name']]
#=> [true, "Azure AD"]
