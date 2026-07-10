# try/integration/api/colonel/list_email_messages_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel recent-messages endpoint (Track B, item 9):
#
#   GET /api/colonel/email/deliverability/messages
#
# Test env resolves determine_provider -> 'logger' (a non-live transport), so
# this asserts the capability=false envelope + pagination param round-trip +
# the auth gates. Lettermint message mapping is covered by the unit tryout with
# an injected fetcher.
#
# Covers:
# - 200 for colonel; details carries the two orthogonal flags + pagination
# - logger transport -> capability false, empty messages
# - page/per_page params round-trip into pagination (per_page clamped 1..100)
# - 403 for non-colonel, 401 for anonymous
#
# Run: try --agent try/integration/api/colonel/list_email_messages_try.rb

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

@colonel = Onetime::Customer.create!(email: "colonel_lem_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_lem_#{@timestamp}@example.com")
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

URL = '/api/colonel/email/deliverability/messages'

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

## Colonel gets 200 with both flags + pagination present
get URL, {}, colonel_headers
@resp = JSON.parse(last_response.body)
@d    = @resp['details']
[last_response.status, @d.key?('capability'), @d.key?('available'), @d.key?('pagination')]
#=> [200, true, true, true]

## logger transport -> capability false, empty messages
[@d['capability'], @d['available'], @d['messages']]
#=> [false, false, []]

## page / per_page round-trip into pagination; per_page clamps to 100
get URL, { 'page' => '2', 'per_page' => '250' }, colonel_headers
@resp = JSON.parse(last_response.body)
@p    = @resp['details']['pagination']
[@p['page'], @p['per_page']]
#=> [2, 100]

# --- Teardown ------------------------------------------------------------
@colonel.destroy! rescue nil
@regular.destroy! rescue nil
