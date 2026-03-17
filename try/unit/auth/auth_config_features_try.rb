# try/unit/auth/auth_config_features_try.rb
#
# frozen_string_literal: true

require_relative '../../../lib/onetime'

# Store original state for teardown
@original_resolve = Onetime::Utils::ConfigResolver.method(:resolve)

# Stub resolve to return test config for 'auth'
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve) do |name|
  return 'spec/auth.test.yaml' if name == 'auth'
  @original_resolve.call(name)
end

# Clear the singleton instance to force fresh load with test config
Onetime::AuthConfig.instance_variable_set(:@singleton__instance__, nil)

## features returns hash from test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.features.class
#=> Hash

## lockout_enabled? returns true with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.lockout_enabled?
#=> true

## password_requirements_enabled? returns true with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.password_requirements_enabled?
#=> true

## active_sessions_enabled? returns true with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.active_sessions_enabled?
#=> true

## remember_me_enabled? returns true with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.remember_me_enabled?
#=> true

## mfa_enabled? returns false with test config (default: false)
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.mfa_enabled?
#=> false

## email_auth_enabled? returns false with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.email_auth_enabled?
#=> false

## webauthn_enabled? returns false with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.webauthn_enabled?
#=> false

## sso_enabled? returns false with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.sso_enabled?
#=> false

## omniauth_enabled? is an alias for sso_enabled?
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_enabled? == config.sso_enabled?
#=> true

## sso_enabled? returns true when legacy 'omniauth' key is used
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features.delete('sso')
features['omniauth'] = true
result = config.sso_enabled?
features.delete('omniauth')
result
#=> true

## sso_enabled? prefers 'sso' key over legacy 'omniauth' key
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features['sso'] = true
features['omniauth'] = false
result = config.sso_enabled?
features['sso'] = false
features.delete('omniauth')
result
#=> true

## sso_display_name falls back to legacy features location
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'full'
cfg['full']['features']['sso'] = true
cfg['full']['features']['sso_display_name'] = 'LegacyIdP'
cfg['full'].delete('sso')
result = config.sso_display_name
cfg['full']['features']['sso'] = false
cfg['full']['features'].delete('sso_display_name')
result
#=> "LegacyIdP"

## sso_only_enabled? returns false when SSO is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.sso_only_enabled?
#=> false

## sso_only_enabled? returns false when SSO enabled but sso_only not set
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features['sso'] = true
result = config.sso_only_enabled?
features['sso'] = false
result
#=> false

## sso_only_enabled? returns true when SSO enabled and sso_only is true
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'full'
cfg['full']['features']['sso'] = true
cfg['full']['sso'] ||= {}
cfg['full']['sso']['sso_only'] = true
ENV['OIDC_ISSUER'] = 'https://example.com'
ENV['OIDC_CLIENT_ID'] = 'test-client'
result = config.sso_only_enabled?
cfg['full']['features']['sso'] = false
cfg['full']['sso']['sso_only'] = false
ENV.delete('OIDC_ISSUER')
ENV.delete('OIDC_CLIENT_ID')
result
#=> true

## omniauth_provider_name returns nil when SSO is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_provider_name
#=> nil

## omniauth_provider_name returns nil for empty string when SSO enabled
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'full'
cfg['full']['features']['sso'] = true
cfg['full']['sso'] ||= {}
cfg['full']['sso']['sso_display_name'] = ''
result = config.omniauth_provider_name
cfg['full']['features']['sso'] = false
result
#=> nil

## omniauth_provider_name returns nil for whitespace-only string when SSO enabled
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'full'
cfg['full']['features']['sso'] = true
cfg['full']['sso'] ||= {}
cfg['full']['sso']['sso_display_name'] = '   '
result = config.omniauth_provider_name
cfg['full']['features']['sso'] = false
result
#=> nil

## omniauth_provider_name returns the name when configured
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'full'
cfg['full']['features']['sso'] = true
cfg['full']['sso'] ||= {}
cfg['full']['sso']['sso_display_name'] = 'Zitadel'
result = config.omniauth_provider_name
cfg['full']['features']['sso'] = false
cfg['full']['sso']['sso_display_name'] = ''
result
#=> "Zitadel"

## verify_account_enabled? returns false in test config (disabled for tests)
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.verify_account_enabled?
#=> false

## All feature methods return false when in simple mode
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'simple'
[
  config.lockout_enabled?,
  config.password_requirements_enabled?,
  config.mfa_enabled?,
  config.email_auth_enabled?,
  config.webauthn_enabled?,
  config.sso_enabled?
]
#=> [false, false, false, false, false, false]

## sso_only_enabled? returns false in simple mode
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'simple'
config.sso_only_enabled?
#=> false

## omniauth_provider_name returns nil in simple mode even if configured
config = Onetime::AuthConfig.instance
cfg = config.instance_variable_get(:@config)
cfg['mode'] = 'simple'
cfg['full']['features']['sso'] = true
cfg['full']['sso'] ||= {}
cfg['full']['sso']['sso_display_name'] = 'Okta'
result = config.omniauth_provider_name
cfg['full']['features']['sso'] = false
cfg['full']['sso']['sso_display_name'] = ''
result
#=> nil

## omniauth_route_name returns nil when SSO is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_route_name
#=> nil

## omniauth_route_name returns 'oidc' by default when SSO is enabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
original_env = ENV['OIDC_ROUTE_NAME']
ENV.delete('OIDC_ROUTE_NAME')
features['sso'] = true
result = config.omniauth_route_name
features['sso'] = false
ENV['OIDC_ROUTE_NAME'] = original_env if original_env
result
#=> "oidc"

## omniauth_route_name returns OIDC_ROUTE_NAME env var when set
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
original_env = ENV['OIDC_ROUTE_NAME']
ENV['OIDC_ROUTE_NAME'] = 'zitadel'
features['sso'] = true
result = config.omniauth_route_name
features['sso'] = false
ENV['OIDC_ROUTE_NAME'] = original_env if original_env
ENV.delete('OIDC_ROUTE_NAME') unless original_env
result
#=> "zitadel"

## omniauth_route_name returns nil in simple mode even if configured
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'simple'
features = config.instance_variable_get(:@config)['full']['features']
features['sso'] = true
result = config.omniauth_route_name
features['sso'] = false
result
#=> nil

## magic_links_enabled? is deprecated alias for email_auth_enabled?
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.magic_links_enabled? == config.email_auth_enabled?
#=> true

# Teardown: Restore original method and clear singleton
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve, @original_resolve)
Onetime::AuthConfig.instance_variable_set(:@singleton__instance__, nil)
