# try/integration/api/colonel/get_email_provider_status_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel provider-status endpoint (Track B):
#
#   GET /api/colonel/email/deliverability/provider-status
#
# Test env resolves determine_provider -> 'logger' (a non-live transport), so
# this asserts the capability=false envelope shape + the auth gates. The SES /
# Lettermint data mapping is exercised by the unit tryout with an injected
# fetcher (test env cannot reach a live provider).
#
# Covers:
# - 200 for colonel; details carries provider + the two orthogonal flags
# - logger transport -> capability false, available false, both blocks nil
# - 403 for non-colonel, 401 for anonymous
#
# Run: try --agent try/integration/api/colonel/get_email_provider_status_try.rb

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

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_geps_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_geps_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}
@regular_session = {
  'authenticated' => true,
  'external_id'   => @regular.extid,
  'email'         => @regular.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

URL = '/api/colonel/email/deliverability/provider-status'

# --- Authorization -------------------------------------------------------

## Non-colonel gets 403
get URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
get URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# --- Colonel read --------------------------------------------------------

## Colonel gets 200
get URL, {}, colonel_headers
last_response.status
#=> 200

## details carries both orthogonal flags + the provider (logger in test env)
@resp = JSON.parse(last_response.body)
@d    = @resp['details']
[@d.key?('capability'), @d.key?('available'), @d['provider']]
#=> [true, true, 'logger']

## logger is a non-live transport: capability false, both provider blocks nil
[@d['capability'], @d['available'], @d['ses'], @d['lettermint']]
#=> [false, false, nil, nil]

# --- Teardown ------------------------------------------------------------
@colonel.destroy! rescue nil
@regular.destroy! rescue nil
