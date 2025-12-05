# try/unit/controllers/homepage_bypass_header_try.rb
#
# frozen_string_literal: true

# Tests for header-based homepage protection bypass
#
# Tests the header_matches_mode? helper from HomepageModeHelpers
# and the integration with homepage mode detection.

require_relative '../../support/test_helpers'

ENV['RACK_ENV'] = 'test'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'rack/test'
require 'rack/mock'

require_relative '../../../apps/web/core/controllers/base'

# Mock controller that includes the Base module
class ::TestController
  include Core::Controllers::Base

  attr_reader :req, :res

  def initialize(req, res)
    @req = req
    @res = res
  end
end

# Helper to create mock request with custom headers
def create_mock_request(headers = {})
  env = Rack::MockRequest.env_for('http://example.com/')

  # Add custom headers
  headers.each do |name, value|
    header_key = name.upcase.tr('-', '_')
    header_key = "HTTP_#{header_key}" unless header_key.start_with?('HTTP_')
    env[header_key] = value
  end

  Rack::Request.new(env)
end

# -------------------------------------------------------------------
# SETUP: Mock OT.conf for testing
# -------------------------------------------------------------------

## Create a test config that we can modify
@test_config = {
  'site' => {
    'interface' => {
      'ui' => {
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
OT.conf.dig('site', 'interface', 'ui', 'homepage', 'mode')
#=> 'protected'

# -------------------------------------------------------------------
# TEST: Method returns true when header matches
# -------------------------------------------------------------------

## Create request with correct header value
@req_with_header = create_mock_request('O-Homepage-Mode' => 'protected')
@controller = TestController.new(@req_with_header, nil)
@controller.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> true

# -------------------------------------------------------------------
# TEST: Method returns nil when header is missing
# -------------------------------------------------------------------

## Create request without the header
@req_without_header = create_mock_request({})
@controller2 = TestController.new(@req_without_header, nil)
@controller2.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> false

# -------------------------------------------------------------------
# TEST: Method returns nil when header has wrong value
# -------------------------------------------------------------------

## Create request with wrong header value
@req_wrong_value = create_mock_request('O-Homepage-Mode' => 'wrong-value')
@controller3 = TestController.new(@req_wrong_value, nil)
@controller3.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> false

# -------------------------------------------------------------------
# TEST: Method returns nil when header is empty
# -------------------------------------------------------------------

## Create request with empty header value
@req_empty_value = create_mock_request('O-Homepage-Mode' => '')
@controller4 = TestController.new(@req_empty_value, nil)
@controller4.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> false

# -------------------------------------------------------------------
# TEST: Case-sensitive header value matching
# -------------------------------------------------------------------

## Create request with capitalized header value
@req_capitalized = create_mock_request('O-Homepage-Mode' => 'Protected')
@controller5 = TestController.new(@req_capitalized, nil)
@controller5.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> false

## Create request with uppercase header value
@req_uppercase = create_mock_request('O-Homepage-Mode' => 'PROTECTED')
@controller6 = TestController.new(@req_uppercase, nil)
@controller6.send(:header_matches_mode?, 'O-Homepage-Mode', 'protected')
#=> false

# -------------------------------------------------------------------
# TEST: Different header name formats
# -------------------------------------------------------------------

## Configure with header containing underscores
@test_config['site']['interface']['ui']['homepage']['request_header'] = 'X_Custom_Header'
OT.conf = @test_config
@req_underscore = create_mock_request('X-Custom-Header' => 'protected')
@controller7 = TestController.new(@req_underscore, nil)
@controller7.send(:header_matches_mode?, 'X_Custom_Header', 'protected')
#=> true

## Configure with header already in HTTP_ format
@test_config['site']['interface']['ui']['homepage']['request_header'] = 'HTTP_X_BYPASS'
OT.conf = @test_config
@req_http_prefix = create_mock_request('X-Bypass' => 'protected')
@controller8 = TestController.new(@req_http_prefix, nil)
@controller8.send(:header_matches_mode?, 'HTTP_X_BYPASS', 'protected')
#=> true

# -------------------------------------------------------------------
# TEST: Method returns nil when mode is not configured
# -------------------------------------------------------------------

## Test with nil mode value (should return false since header doesn't match nil)
@test_config['site']['interface']['ui']['homepage']['mode'] = nil
OT.conf = @test_config
@req_no_mode = create_mock_request('O-Homepage-Mode' => 'protected')
@controller9 = TestController.new(@req_no_mode, nil)
@controller9.send(:header_matches_mode?, 'O-Homepage-Mode', nil)
#=> false

# -------------------------------------------------------------------
# TEST: Method returns nil when mode is different
# -------------------------------------------------------------------

## Test with different expected mode value
@test_config['site']['interface']['ui']['homepage']['mode'] = 'some-other-mode'
OT.conf = @test_config
@req_other_mode = create_mock_request('O-Homepage-Mode' => 'protected')
@controller10 = TestController.new(@req_other_mode, nil)
@controller10.send(:header_matches_mode?, 'O-Homepage-Mode', 'some-other-mode')
#=> false

# -------------------------------------------------------------------
# TEST: Method returns nil when request_header is not configured
# -------------------------------------------------------------------

## Test with nil header name (should return false)
@test_config['site']['interface']['ui']['homepage']['mode'] = 'protected'
@test_config['site']['interface']['ui']['homepage']['request_header'] = nil
OT.conf = @test_config
@req_no_header_config = create_mock_request('O-Homepage-Mode' => 'protected')
@controller11 = TestController.new(@req_no_header_config, nil)
@controller11.send(:header_matches_mode?, nil, 'protected')
#=> false

# -------------------------------------------------------------------
# TEST: Method returns nil when request_header is empty string
# -------------------------------------------------------------------

## Test with empty header name (should return false)
@test_config['site']['interface']['ui']['homepage']['request_header'] = ''
OT.conf = @test_config
@req_empty_header_config = create_mock_request('O-Homepage-Mode' => 'protected')
@controller12 = TestController.new(@req_empty_header_config, nil)
@controller12.send(:header_matches_mode?, '', 'protected')
#=> false

# -------------------------------------------------------------------
# TEARDOWN: Remove config override
# -------------------------------------------------------------------

## Remove the test config override
OT.instance_variable_set(:@test_config_override, nil)
true
#=> true
