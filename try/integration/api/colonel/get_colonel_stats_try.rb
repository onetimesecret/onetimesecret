# try/integration/api/colonel/get_colonel_stats_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel stats endpoint:
#
#   GET /api/colonel/stats
#
# Part of the colonel admin rebuild backend-debt fix (issue #3653, debt §7).
# `secrets_created`, `secrets_shared`, and `emails_sent` were previously stubbed
# to a hardcoded 0. They are now sourced from the real global Familia class
# counters (Onetime::Customer.<name>) maintained at the creation/send chokepoints.
#
# Covers:
# - 403 for non-colonel users, 401 for anonymous
# - the three formerly-stubbed fields reflect the live counters, not 0
# - all count fields are present with the expected shape
#
# Run: try --agent try/integration/api/colonel/get_colonel_stats_try.rb

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

# Colonel user (role persisted so session auth reads it)
@colonel = Onetime::Customer.create!(email: "colonel_stats_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

# Regular (non-colonel) customer
@regular = Onetime::Customer.create!(email: "regular_stats_#{@timestamp}@example.com")
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

# TRYOUTS

## Anonymous (no session) gets 401
@test.clear_cookies
get '/api/colonel/stats', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403
get '/api/colonel/stats', {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Colonel gets 200 with the counts block
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['details']['counts'].is_a?(Hash)]
#=> [200, true]

## secrets_created reflects the live global counter (not a hardcoded 0)
Onetime::Customer.secrets_created.increment
Onetime::Customer.secrets_created.increment
@live_created = Onetime::Customer.secrets_created.to_i
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
counts = JSON.parse(last_response.body)['details']['counts']
[counts['secrets_created'] == @live_created, counts['secrets_created'].positive?]
#=> [true, true]

## secrets_shared reflects the live global counter (not a hardcoded 0)
Onetime::Customer.secrets_shared.increment
@live_shared = Onetime::Customer.secrets_shared.to_i
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
counts = JSON.parse(last_response.body)['details']['counts']
[counts['secrets_shared'] == @live_shared, counts['secrets_shared'].positive?]
#=> [true, true]

## emails_sent reflects the live global counter (not a hardcoded 0)
Onetime::Customer.emails_sent.increment
@live_emails = Onetime::Customer.emails_sent.to_i
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
counts = JSON.parse(last_response.body)['details']['counts']
[counts['emails_sent'] == @live_emails, counts['emails_sent'].positive?]
#=> [true, true]

## session_count reflects real session keys, not a hardcoded 0 (QA 2026-07-07)
@session_key = "session:stats_try_#{@timestamp}"
Familia.dbclient.set(@session_key, JSON.generate({ 'authenticated' => true }))
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
counts = JSON.parse(last_response.body)['details']['counts']
[counts['session_count'].is_a?(Integer), counts['session_count'].positive?]
#=> [true, true]

## the counts block still exposes the full expected key set
get '/api/colonel/stats', {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
JSON.parse(last_response.body)['details']['counts'].keys.sort
#=> ["customer_count", "emails_sent", "receipt_count", "secret_count", "secrets_created", "secrets_shared", "session_count"]

# TEARDOWN

Familia.dbclient.del(@session_key)
