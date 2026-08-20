# try/integration/api/v2/v2_meta_version_auth_try.rb
#
# frozen_string_literal: true

#
# Auth gating for the V2 meta endpoints.
#
# GET /api/v2/version discloses the exact build version, which is the primary
# input to fingerprinting an install and matching it against known CVEs. It is
# gated by auth=sessionauth,basicauth, so anonymous callers get 401.
#
# The sibling meta endpoints stay public: /status and /supported-locales
# disclose nothing about the build.
#
# The V3 equivalent lives in
# try/integration/api/v3/meta_endpoints_contract_try.rb, which also pins the
# response shape. This file covers the V2 gate, since V2 is the stable API and
# the one external integrations call.

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args); @test.get(*args); end
def last_response; @test.last_response; end
def clear_cookies; @test.clear_cookies; end

@cust   = Onetime::Customer.create!(email: generate_unique_test_email('v2_meta'))
@apikey = "meta_v2_#{SecureRandom.hex(8)}"
@cust.apitoken = @apikey
@cust.save

@auth_headers = {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@cust.email}:#{@apikey}")}",
}

## V2 version endpoint rejects anonymous callers
clear_cookies
get '/api/v2/version', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## V2 version endpoint does not leak the version in the rejection body
# A 401 that still prints the version would defeat the gate entirely.
clear_cookies
get '/api/v2/version', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.body.include?(OT::VERSION.to_s)
#=> false

## V2 version endpoint rejects an invalid API key
clear_cookies
get '/api/v2/version', {}, {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@cust.email}:wrong_key")}",
}
last_response.status
#=> 401

## V2 version endpoint returns 200 for an authenticated caller
clear_cookies
get '/api/v2/version', {}, @auth_headers
last_response.status
#=> 200

## V2 version response still carries the version components
@version_response = JSON.parse(last_response.body)
@version_response['version'].is_a?(Array) && @version_response['version'].length >= 3
#=> true

## V2 status endpoint stays public
# Unchanged by the version gate: it reports operational state, not build info.
clear_cookies
get '/api/v2/status', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V2 status response discloses no build version
clear_cookies
get '/api/v2/status', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.body.include?(OT::VERSION.to_s)
#=> false

## V2 supported-locales endpoint stays public
clear_cookies
get '/api/v2/supported-locales', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

# Teardown
@cust.destroy!
