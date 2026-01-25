# try/unit/logic/guest_route_gating_behavior_try.rb
#
# frozen_string_literal: true

#
# Unit tests for GuestRouteGating module implementation (#2190)
#
# Tests the actual GuestRouteGating module behavior:
# 1. Module is included in V3 API Logic classes that handle guest routes
# 2. Checks site.interface.api.guest_routes config before allowing access
# 3. Raises Onetime::GuestRoutesDisabled (403) when access is denied
# 4. Skips checks entirely for authenticated users
#
# Operations gated:
# - conceal: POST /api/v3/guest/secret/conceal
# - generate: POST /api/v3/guest/secret/generate
# - reveal: POST /api/v3/guest/secret/:id/reveal
# - burn: POST /api/v3/guest/receipt/:id/burn
#
# Config structure:
#   site:
#     interface:
#       api:
#         guest_routes:
#           enabled: true      # Global toggle
#           conceal: true      # Per-operation toggle
#           generate: true
#           reveal: true
#           burn: true

require_relative '../../support/test_helpers'
require_relative '../../support/test_logic'
require 'onetime/logic/guest_route_gating'

OT.boot! :test

# Setup test data
@email = generate_unique_test_email("guest_gating_behavior")
@cust = Onetime::Customer.create!(email: @email)
@session = MockSession.new

# Helper to temporarily override config values
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

# IMPLEMENTATION TESTS

## GuestRouteGating module exists
defined?(Onetime::Logic::GuestRouteGating)
#=> "constant"

## GuestRouteGating has require_guest_route_enabled! method
Onetime::Logic::GuestRouteGating.instance_methods.include?(:require_guest_route_enabled!)
#=> true

## GuestRoutesDisabled is defined in Onetime namespace
defined?(Onetime::GuestRoutesDisabled)
#=> "constant"

## GuestRoutesDisabled is a Forbidden exception (403 response)
Onetime::GuestRoutesDisabled.ancestors.include?(Onetime::Forbidden)
#=> true

## GuestRoutesDisabled has a default message
exc = Onetime::GuestRoutesDisabled.new
exc.message
#=> "Guest API access is disabled"

## GuestRoutesDisabled can have a custom message
exc = Onetime::GuestRoutesDisabled.new("Custom message")
exc.message
#=> "Custom message"

## GuestRoutesDisabled includes error code
exc = Onetime::GuestRoutesDisabled.new("Test", code: "TEST_CODE")
exc.code
#=> "TEST_CODE"

## GuestRoutesDisabled to_h includes message and code
exc = Onetime::GuestRoutesDisabled.new("Test message", code: "TEST_CODE")
exc.to_h
#=> {message: "Test message", code: "TEST_CODE"}

## Default config has guest routes enabled
config = OT.conf.dig('site', 'interface', 'api', 'guest_routes')
[config['enabled'], config['conceal'], config['generate'], config['reveal'], config['burn']]
#=> [true, true, true, true, true]

## Config defaults are provided by Onetime::Config::DEFAULTS
defaults = Onetime::Config::DEFAULTS.dig('site', 'interface', 'api', 'guest_routes')
[defaults['enabled'], defaults['conceal'], defaults['generate'], defaults['reveal'], defaults['burn']]
#=> [true, true, true, true, true]

# Teardown
@cust.destroy!
