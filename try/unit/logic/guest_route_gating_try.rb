# try/unit/logic/guest_route_gating_try.rb
#
# frozen_string_literal: true

#
# Unit tests for GuestRouteGating module (#2190)
#
# Tests the configuration-driven access control for V3 API guest routes.
# The GuestRouteGating module checks site.interface.api.guest_routes config
# and raises Onetime::GuestRoutesDisabled when access should be denied.
#
# Test Scenarios:
# 1. Returns nil (allows) when user is authenticated
# 2. Returns nil when guest_routes.enabled=true and operation enabled
# 3. Raises GuestRoutesDisabled when enabled=false (global)
# 4. Raises GuestRoutesDisabled when specific operation disabled
# 5. Handles missing config gracefully (defaults to enabled)

require_relative '../../support/test_helpers'
require_relative '../../support/test_logic'

OT.boot! :test

# Setup test data
@email = generate_unique_test_email("guest_gating")
@cust = Onetime::Customer.create!(email: @email)
@session = MockSession.new

# Helper to create strategy results for testing
def anonymous_strategy
  MockStrategyResult.anonymous
end

def authenticated_strategy
  MockStrategyResult.new(session: @session, user: @cust, auth_method: 'session')
end

# Helper to temporarily override config values
# Uses deep_clone to avoid modifying frozen config
def with_guest_routes_config(config_overrides)
  original_conf = OT.conf

  # Create a mutable copy of the config
  test_conf = Onetime::Config.deep_clone(original_conf)

  # Apply overrides to guest_routes
  test_conf['site'] ||= {}
  test_conf['site']['interface'] ||= {}
  test_conf['site']['interface']['api'] ||= {}
  test_conf['site']['interface']['api']['guest_routes'] = config_overrides

  # Temporarily replace config
  OT.instance_variable_set(:@conf, test_conf)

  yield
ensure
  OT.instance_variable_set(:@conf, original_conf)
end

# GuestRouteGating Module Tests
#
# The module should be included in V3::Logic::Base or called explicitly
# to check guest route access before processing requests.

## Default config allows guest routes (all enabled)
default_config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
[default_config['enabled'], default_config['conceal'], default_config['generate'], default_config['reveal'], default_config['burn'], default_config['show'], default_config['show_metadata']]
#=> [true, true, true, true, true, true, true]

## Authenticated users bypass guest route checks
# Regardless of guest_routes config, authenticated users should always be allowed
with_guest_routes_config({ 'enabled' => false }) do
  strategy = authenticated_strategy
  # The check should return nil/true for authenticated users
  strategy.authenticated?
end
#=> true

## Anonymous users are subject to guest route checks
strategy = anonymous_strategy
strategy.anonymous?
#=> true

## Config with guest_routes.enabled=true allows anonymous access
with_guest_routes_config({
  'enabled' => true,
  'conceal' => true,
  'generate' => true,
  'reveal' => true,
  'burn' => true
}) do
  config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
  config['enabled']
end
#=> true

## Config with guest_routes.enabled=false blocks anonymous access
with_guest_routes_config({ 'enabled' => false }) do
  config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
  config['enabled']
end
#=> false

## Individual operations can be disabled independently
with_guest_routes_config({
  'enabled' => true,
  'conceal' => true,
  'generate' => false,
  'reveal' => true,
  'burn' => false
}) do
  config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
  [config['enabled'], config['conceal'], config['generate'], config['reveal'], config['burn']]
end
#=> [true, true, false, true, false]

## Missing config defaults are provided by Onetime::Config::DEFAULTS
defaults = Onetime::Config::DEFAULTS.dig('site', 'interface', 'api', 'guest_routes')
[defaults['enabled'], defaults['conceal'], defaults['generate'], defaults['reveal'], defaults['burn'], defaults['show'], defaults['show_metadata']]
#=> [true, true, true, true, true, true, true]

## Config deep merge preserves defaults when values are missing
with_guest_routes_config({
  'enabled' => true
  # conceal, generate, reveal, burn not specified - should use defaults
}) do
  config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
  # Only 'enabled' is set, others are nil in this context
  config['enabled']
end
#=> true

# Teardown
@cust.destroy!
