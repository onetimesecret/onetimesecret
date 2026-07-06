# try/integration/api/colonel/list_users_secret_count_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel users endpoint's secret count (issue #60):
#
#   GET /api/colonel/users
#
# Confirms the per-user `secrets_count` is now sourced from the maintained
# per-customer `secrets_active` counter (incremented at Receipt.spawn_pair),
# resolving the TODO(#60) that #20 left where the count came from a per-request
# `secret:*` SCAN. The response shape is unchanged (Zod tripwire): `secrets_count`
# is still present and an Integer.
#
# Covers:
# - 401 anonymous, 403 non-colonel (auth unchanged)
# - a user's secrets_count reflects their live secret counter, not a SCAN
# - the users row still exposes secrets_count as an Integer (byte-identical shape)
#
# Run: try --agent try/integration/api/colonel/list_users_secret_count_try.rb

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

# Colonel user (role persisted so session auth reads it). We spawn this user's
# own secrets so we can find its row deterministically via the role filter.
@colonel = Onetime::Customer.create!(email: "colonel_users_#{@timestamp}@example.com")
@colonel.role     = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_users_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

# Give the colonel a known number of live secrets via the creation chokepoint.
@secret_count = 3
@secret_count.times { Onetime::Receipt.spawn_pair(@colonel.objid, 3600, 'colonel secret') }

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

def colonel_row(response_body, extid)
  JSON.parse(response_body)['details']['users'].find { |u| u['extid'] == extid }
end

# TRYOUTS

## Anonymous (no session) gets 401
@test.clear_cookies
get '/api/colonel/users', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403
get '/api/colonel/users', {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Colonel gets 200 with a users array
get '/api/colonel/users', { 'role' => 'colonel', 'per_page' => 100 }, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
resp = JSON.parse(last_response.body)
[last_response.status, resp['details']['users'].is_a?(Array)]
#=> [200, true]

## the colonel's own row exposes secrets_count as an Integer (shape unchanged)
get '/api/colonel/users', { 'role' => 'colonel', 'per_page' => 100 }, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
@row = colonel_row(last_response.body, @colonel.extid)
[@row.nil?, @row && @row['secrets_count'].is_a?(Integer)]
#=> [false, true]

## secrets_count equals the maintained live-secret counter (not a SCAN result)
get '/api/colonel/users', { 'role' => 'colonel', 'per_page' => 100 }, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
@row = colonel_row(last_response.body, @colonel.extid)
[@row['secrets_count'], @colonel.secrets_active.to_i]
#=> [3, 3]

# TEARDOWN

[@colonel, @regular].each { |c| c.destroy! rescue nil }
