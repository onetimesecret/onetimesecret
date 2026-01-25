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

## hardening_enabled? returns true with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.hardening_enabled?
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

## omniauth_enabled? returns false with test config
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_enabled?
#=> false

## omniauth_provider_name returns nil when omniauth is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_provider_name
#=> nil

## omniauth_provider_name returns nil for empty string when omniauth enabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features['omniauth'] = true
features['sso_display_name'] = ''
result = config.omniauth_provider_name
features['omniauth'] = false
result
#=> nil

## omniauth_provider_name returns nil for whitespace-only string when omniauth enabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features['omniauth'] = true
features['sso_display_name'] = '   '
result = config.omniauth_provider_name
features['omniauth'] = false
result
#=> nil

## omniauth_provider_name returns the name when configured
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
features['omniauth'] = true
features['sso_display_name'] = 'Zitadel'
result = config.omniauth_provider_name
features['omniauth'] = false
features['sso_display_name'] = ''
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
  config.hardening_enabled?,
  config.mfa_enabled?,
  config.email_auth_enabled?,
  config.webauthn_enabled?,
  config.omniauth_enabled?
]
#=> [false, false, false, false, false]

## omniauth_provider_name returns nil in simple mode even if configured
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'simple'
features = config.instance_variable_get(:@config)['full']['features']
features['omniauth'] = true
features['sso_display_name'] = 'Okta'
result = config.omniauth_provider_name
features['omniauth'] = false
features['sso_display_name'] = ''
result
#=> nil

## omniauth_route_name returns nil when omniauth is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.omniauth_route_name
#=> nil

## omniauth_route_name returns 'oidc' by default when omniauth is enabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
original_env = ENV['OIDC_ROUTE_NAME']
ENV.delete('OIDC_ROUTE_NAME')
features['omniauth'] = true
result = config.omniauth_route_name
features['omniauth'] = false
ENV['OIDC_ROUTE_NAME'] = original_env if original_env
result
#=> "oidc"

## omniauth_route_name returns OIDC_ROUTE_NAME env var when set
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
original_env = ENV['OIDC_ROUTE_NAME']
ENV['OIDC_ROUTE_NAME'] = 'zitadel'
features['omniauth'] = true
result = config.omniauth_route_name
features['omniauth'] = false
ENV['OIDC_ROUTE_NAME'] = original_env if original_env
ENV.delete('OIDC_ROUTE_NAME') unless original_env
result
#=> "zitadel"

## omniauth_route_name returns nil in simple mode even if configured
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'simple'
features = config.instance_variable_get(:@config)['full']['features']
features['omniauth'] = true
result = config.omniauth_route_name
features['omniauth'] = false
result
#=> nil

## magic_links_enabled? is deprecated alias for email_auth_enabled?
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.magic_links_enabled? == config.email_auth_enabled?
#=> true

## security_features_enabled? combines hardening, active_sessions, remember_me
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
config.security_features_enabled?
#=> true

## security_features_enabled? returns false when any underlying feature is disabled
config = Onetime::AuthConfig.instance
config.instance_variable_get(:@config)['mode'] = 'full'
features = config.instance_variable_get(:@config)['full']['features']
original_remember_me = features['remember_me']
features['remember_me'] = false
result = config.security_features_enabled?
features['remember_me'] = original_remember_me
result
#=> false

# Teardown: Restore original method and clear singleton
Onetime::Utils::ConfigResolver.define_singleton_method(:resolve, @original_resolve)
Onetime::AuthConfig.instance_variable_set(:@singleton__instance__, nil)
