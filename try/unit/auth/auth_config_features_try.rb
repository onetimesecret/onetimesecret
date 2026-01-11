# try/unit/auth/auth_config_features_try.rb
#
# Tests for AuthConfig feature flag methods that read from YAML config.
# Verifies the ENV → YAML → AuthConfig pipeline works correctly.
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
  config.webauthn_enabled?
]
#=> [false, false, false, false]

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
