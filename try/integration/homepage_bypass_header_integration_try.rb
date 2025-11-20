# try/integration/homepage_bypass_header_integration_try.rb
#
# frozen_string_literal: true

# Integration tests for header-based homepage protection bypass
#
# Tests the full flow from controller through view serialization to
# ensure the homepage_bypass_header flag is properly passed to the frontend.

require_relative '../support/test_helpers'

ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'onetime/middleware'
require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

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

# -------------------------------------------------------------------
# TEST: Homepage with bypass header shows homepage_bypass_header: true
# -------------------------------------------------------------------

## Request homepage with bypass header
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'protected' }
@test.last_response.status
#=> 200

## Extract window state from response
@html = @test.last_response.body
@script_match = @html.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@script_match.nil?
#=> false

## Parse the JSON
@window_state = JSON.parse(@script_match[1])
@window_state['homepage_mode']
#=> 'protected'

## Verify authentication.required is still true (not overridden at config level)
@window_state['authentication']['required']
#=> true

# -------------------------------------------------------------------
# TEST: Homepage without bypass header shows homepage_bypass_header: nil
# -------------------------------------------------------------------

## Request homepage without bypass header
@test.get '/', {}, {}
@test.last_response.status
#=> 200

## Extract window state from response
@html2 = @test.last_response.body
@script_match2 = @html2.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@window_state2 = JSON.parse(@script_match2[1])
@window_state2['homepage_bypass_header']
#=> nil

# -------------------------------------------------------------------
# TEST: Homepage with wrong header value shows homepage_bypass_header: nil
# -------------------------------------------------------------------

## Request homepage with wrong header value
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'wrong-value' }
@test.last_response.status
#=> 200

## Extract window state
@html3 = @test.last_response.body
@script_match3 = @html3.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@window_state3 = JSON.parse(@script_match3[1])
@window_state3['homepage_bypass_header']
#=> nil

# -------------------------------------------------------------------
# TEST: Mode disabled - bypass header has no effect
# -------------------------------------------------------------------

## Disable the mode
@test_config['site']['interface']['ui']['homepage']['mode'] = 'normal'
OT.conf = @test_config

## Request homepage with bypass header
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'protected' }
@test.last_response.status
#=> 200

## Extract window state
@html4 = @test.last_response.body
@script_match4 = @html4.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@window_state4 = JSON.parse(@script_match4[1])
@window_state4['homepage_bypass_header']
#=> nil

# -------------------------------------------------------------------
# TEST: Different header name configuration
# -------------------------------------------------------------------

## Configure different header name
@test_config['site']['interface']['ui']['homepage']['mode'] = 'protected_by_request_header'
@test_config['site']['interface']['ui']['homepage']['request_header'] = 'X-Internal-Access'
OT.conf = @test_config

## Request with new header name
@test.get '/', {}, { 'HTTP_X_INTERNAL_ACCESS' => 'protected' }
@test.last_response.status
#=> 200

## Extract window state
@html5 = @test.last_response.body
@script_match5 = @html5.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@window_state5 = JSON.parse(@script_match5[1])
@window_state5['homepage_bypass_header']
#=> true

## Request with old header name (should not work)
@test.get '/', {}, { 'HTTP_O_HOMEPAGE_MODE' => 'protected' }
@html6 = @test.last_response.body
@script_match6 = @html6.match(/window\.__ONETIME_STATE__\s*=\s*({.*?});/m)
@window_state6 = JSON.parse(@script_match6[1])
@window_state6['homepage_bypass_header']
#=> nil

# -------------------------------------------------------------------
# TEARDOWN: Remove config override
# -------------------------------------------------------------------

## Remove the test config override
OT.instance_variable_set(:@test_config_override, nil)
true
#=> true
