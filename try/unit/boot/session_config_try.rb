# try/unit/boot/session_config_try.rb
#
# frozen_string_literal: true

# Session Configuration Test Suite
#
# Tests session cookie configuration, specifically the SameSite attribute.
#
# Issue #2405: Changed SameSite from 'strict' to 'lax' to fix Stripe checkout
# redirects. With 'strict', the session cookie was not sent on cross-site GET
# navigations (e.g., returning from Stripe checkout), causing session loss.
#
# SameSite behavior:
#   - strict: Cookie not sent on ANY cross-site request (breaks OAuth/payment redirects)
#   - lax: Cookie sent on cross-site GET navigations (safe for redirects)
#   - none: Cookie sent on all cross-site requests (requires Secure flag)

require_relative '../../support/test_helpers'

OT.boot! :test, false

# Convenience alias - SESSION_DEFAULTS is defined in Onetime::Initializers module
# which Onetime extends, making it available as Onetime::Initializers::SESSION_DEFAULTS
SessionDefaults = Onetime::Initializers::SESSION_DEFAULTS

## SESSION_DEFAULTS includes same_site key
SessionDefaults.key?('same_site')
#=> true

## SESSION_DEFAULTS same_site is 'lax' (not 'strict')
# Required for Stripe/OAuth redirects - 'strict' blocks cookies on cross-site GET navigations
SessionDefaults['same_site']
#=> 'lax'

## SESSION_DEFAULTS has expected structure
keys = SessionDefaults.keys.sort
keys
#=> ['expire_after', 'httponly', 'key', 'same_site']

## SESSION_DEFAULTS is frozen (immutable)
SessionDefaults.frozen?
#=> true

## session_config returns 'lax' for same_site when not overridden
# The test config (spec/config.test.yaml) sets same_site: lax
Onetime.session_config['same_site']
#=> 'lax'

## session_config merges user config over defaults
# Verify the merge behavior works correctly
config = Onetime.session_config
[config.key?('same_site'), config.key?('expire_after'), config.key?('key')]
#=> [true, true, true]

## session_config includes httponly by default
Onetime.session_config['httponly']
#=> true

## session_config includes secure from site config or SSL fallback
# In test environment, secure should be false (spec/config.test.yaml)
Onetime.session_config['secure']
#=> false

## same_site value is valid (strict, lax, or none)
valid_values = %w[strict lax none]
valid_values.include?(Onetime.session_config['same_site'])
#=> true

## Middleware stack uses same_site as symbol
# The middleware_stack.rb converts same_site to symbol via .to_sym
# This test verifies the value can be safely converted
Onetime.session_config['same_site'].to_sym
#=> :lax

## Config file same_site matches SESSION_DEFAULTS expectation
# Both should be 'lax' for consistent behavior
[SessionDefaults['same_site'], Onetime.session_config['same_site']]
#=> ['lax', 'lax']
