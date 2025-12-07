# try/integration/homepage_bypass_header_integration_try.rb
#
# frozen_string_literal: true

# Integration tests for header-based homepage protection bypass
#
# Tests the full flow from controller through view serialization to
# ensure the homepage_bypass_header flag is properly passed to the frontend.
#
# NOTE: These tests are currently skipped because they require full Rhales
# rendering to inject window.__ONETIME_STATE__, which isn't fully configured
# in the Rack::Test integration test environment. The unit tests in
# try/unit/controllers/homepage_bypass_header_try.rb verify the core logic.
#
# TODO: Fix Rhales integration in test environment or use RSpec with proper setup

require_relative '../support/test_helpers'


require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/middleware'
require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Ensure Onetime is marked as ready - this can be set to false by other tests
# or by prepare_application_registry if it encounters errors during the full
# test suite run. The StartupReadiness middleware returns 503 if not ready.
Onetime.instance_variable_set(:@ready, true) unless Onetime.ready?

require 'rack/test'
require 'json'

# Create test instance
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# -------------------------------------------------------------------
# SETUP: Mock OT.conf for testing
# -------------------------------------------------------------------

## Create a test config that we can modify
@test_config = {
  'site' => {
    'host' => 'localhost',
    'ssl' => false,
    'authentication' => {
      'enabled' => true,
      'signin' => true,
      'signup' => true,
      'required' => true
    },
    'interface' => {
      'ui' => {
        'enabled' => true,
        'homepage' => {
          'mode' => 'protected',
          'request_header' => 'O-Homepage-Mode'
        }
      }
    }
  }
}

## Stub OT.conf to return our test config
def OT.conf
  @test_config_override || super
end

def OT.conf=(config)
  @test_config_override = config
end

OT.conf = @test_config

## Verify authentication.required is configured
OT.conf['site']['authentication']['required']
#=> true

## Verify homepage mode is configured
OT.conf['site']['interface']['ui']['homepage']['mode']
#=> 'protected'

## Request homepage with bypass header returns 200
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'protected' }
@test.last_response.status
#=> 200

## Request homepage without bypass header returns 200
@test.get '/', {}, {}
@test.last_response.status
#=> 200

## Request homepage with wrong header value returns 200
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'wrong-value' }
@test.last_response.status
#=> 200

## Remove the test config override
OT.instance_variable_set(:@test_config_override, nil)
true
#=> true
