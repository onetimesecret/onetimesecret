# try/integration/api/v3/meta_endpoints_contract_try.rb
#
# frozen_string_literal: true

#
# Contract tests for V3 meta endpoints (#2686)
#
# Verifies V3 meta endpoints follow pure REST conventions:
# - HTTP status codes indicate success/error
# - Response bodies do NOT contain a `success` field
# - Response bodies contain only the documented fields
#
# Endpoints:
# - GET /api/v3/status           -> { status, locale }  (public)
# - GET /api/v3/version          -> { version, locale }  (authenticated)
# - GET /api/v3/supported-locales -> { locales, default_locale, locale }  (public)
#
# /version is gated by auth=sessionauth,basicauth: the exact build version
# fingerprints the install for CVE matching, so it is not disclosed to
# anonymous callers. The response contract below is exercised over an
# API-key (basicauth) request.

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

# Create test instance with Rack::Test::Methods
@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

# Delegate Rack::Test methods to @test
def get(*args); @test.get(*args); end
def last_response; @test.last_response; end
def clear_cookies; @test.clear_cookies; end

# API-key customer used for the authenticated /version contract checks.
@cust = Onetime::Customer.create!(email: generate_unique_test_email('v3_meta'))
@apikey = "meta_contract_#{SecureRandom.hex(8)}"
@cust.apitoken = @apikey
@cust.save

@auth_headers = {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@cust.email}:#{@apikey}")}",
}

# ---------------------------------------------------------------------------
# /api/v3/status contract tests
# ---------------------------------------------------------------------------

## V3 status endpoint returns 200
clear_cookies
get '/api/v3/status', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V3 status response is valid JSON
@status_response = JSON.parse(last_response.body)
@status_response.is_a?(Hash)
#=> true

## V3 status response contains 'status' field
@status_response.key?('status')
#=> true

## V3 status response contains 'locale' field
@status_response.key?('locale')
#=> true

## V3 status response does NOT contain 'success' field (pure REST)
@status_response.key?('success')
#=> false

## V3 status response has exactly 2 fields
@status_response.keys.sort
#=> ['locale', 'status']

## V3 status field is 'nominal'
@status_response['status']
#=> 'nominal'

# ---------------------------------------------------------------------------
# /api/v3/version contract tests
# ---------------------------------------------------------------------------

## V3 version endpoint rejects anonymous callers
# Build version disclosure is the fingerprinting input for CVE matching, so
# /version fails closed for anonymous requests (unlike /status and
# /supported-locales, which disclose nothing about the build).
clear_cookies
get '/api/v3/version', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## V3 version endpoint rejects an invalid API key
clear_cookies
get '/api/v3/version', {}, {
  'HTTP_ACCEPT' => 'application/json',
  'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{@cust.email}:wrong_key")}",
}
last_response.status
#=> 401

## V3 version endpoint returns 200 for an authenticated caller
clear_cookies
get '/api/v3/version', {}, @auth_headers
last_response.status
#=> 200

## V3 version response is valid JSON
@version_response = JSON.parse(last_response.body)
@version_response.is_a?(Hash)
#=> true

## V3 version response contains 'version' field
@version_response.key?('version')
#=> true

## V3 version response contains 'locale' field
@version_response.key?('locale')
#=> true

## V3 version response does NOT contain 'success' field (pure REST)
@version_response.key?('success')
#=> false

## V3 version response has exactly 2 fields
@version_response.keys.sort
#=> ['locale', 'version']

## V3 version field is an array
@version_response['version'].is_a?(Array)
#=> true

## V3 version array has at least 3 components (major, minor, patch)
@version_response['version'].length >= 3
#=> true

# ---------------------------------------------------------------------------
# /api/v3/supported-locales contract tests
# ---------------------------------------------------------------------------

## V3 supported-locales endpoint returns 200
clear_cookies
get '/api/v3/supported-locales', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 200

## V3 supported-locales response is valid JSON
@locales_response = JSON.parse(last_response.body)
@locales_response.is_a?(Hash)
#=> true

## V3 supported-locales response contains 'locales' field
@locales_response.key?('locales')
#=> true

## V3 supported-locales response contains 'default_locale' field
@locales_response.key?('default_locale')
#=> true

## V3 supported-locales response contains 'locale' field
@locales_response.key?('locale')
#=> true

## V3 supported-locales response does NOT contain 'success' field (pure REST)
@locales_response.key?('success')
#=> false

## V3 supported-locales response has exactly 3 fields
@locales_response.keys.sort
#=> ['default_locale', 'locale', 'locales']

## V3 locales field is an array
@locales_response['locales'].is_a?(Array)
#=> true

## V3 locales array is non-empty
@locales_response['locales'].length > 0
#=> true

## V3 default_locale is included in locales array
@locales_response['locales'].include?(@locales_response['default_locale'])
#=> true

# Teardown
@cust.destroy!
