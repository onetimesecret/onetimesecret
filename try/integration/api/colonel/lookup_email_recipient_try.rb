# try/integration/api/colonel/lookup_email_recipient_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel recipient-lookup endpoint (Track B, item 10):
#
#   GET /api/colonel/email/deliverability/lookup?address=
#
# Test env resolves determine_provider -> 'logger', so provider_result is nil
# (capability false), but the LOCAL suppression store is real and is always
# returned. Covers:
# - 200 with ?address=; details.local always present, keyed by normalized addr
# - a stored suppression is reflected in details.local (real Valkey read)
# - missing/blank ?address= -> 422 form error
# - 403 for non-colonel, 401 for anonymous
#
# Run: try --agent try/integration/api/colonel/lookup_email_recipient_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry
require 'onetime/models/email_suppression'

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

SUP = Onetime::EmailSuppression

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_ler_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_ler_#{@timestamp}@example.com")
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

@addr = "lookup_int_#{@timestamp}@example.com"
SUP.remove!(@addr)

URL = '/api/colonel/email/deliverability/lookup'

# --- Authorization -------------------------------------------------------

## Non-colonel gets 403
get URL, { 'address' => @addr }, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
get URL, { 'address' => @addr }, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# --- Validation ----------------------------------------------------------

## Missing address -> 422 form error
get URL, {}, colonel_headers
last_response.status
#=> 422

## Blank address -> 422 form error
get URL, { 'address' => '   ' }, colonel_headers
last_response.status
#=> 422

# --- Local store is always present (not suppressed) ----------------------

## unknown address -> 200, local present with suppressed=false
get URL, { 'address' => @addr }, colonel_headers
@resp = JSON.parse(last_response.body)
@d    = @resp['details']
[last_response.status, @d['address'], @d['local']['suppressed'], @d.key?('provider_result')]
#=> [200, @addr, false, true]

# --- A stored suppression is reflected in details.local ------------------

## suppress the address, then the lookup local block shows it (normalized key)
SUP.suppress!(address: @addr, reason: 'bounce', source: 'manual')
get URL, { 'address' => @addr.upcase }, colonel_headers
@resp = JSON.parse(last_response.body)
@d    = @resp['details']
[@d['address'], @d['local']['suppressed'], @d['local']['reason'], @d['local']['source']]
#=> [@addr, true, 'bounce', 'manual']

# --- Teardown ------------------------------------------------------------
SUP.remove!(@addr) rescue nil
@colonel.destroy!  rescue nil
@regular.destroy!  rescue nil
