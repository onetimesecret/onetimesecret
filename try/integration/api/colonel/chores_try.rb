# try/integration/api/colonel/chores_try.rb
#
# frozen_string_literal: true

# Integration tests for the console chore endpoints (#4343) over the real Rack
# stack:
#
#   GET  /api/colonel/chores
#   POST /api/colonel/chores/:chore/run
#
# Covers:
# - 401 anonymous, 403 non-colonel
# - the list is the catalog, without the excluded vhost cleanup
# - a dotted chore id routes through `:chore`, and a JSON body's dry_run and
#   limit reach the logic
# - a housekeeping dry run needs no confirmation and writes no run record
# - a live run without X-OTS-Confirm is refused; with it, it runs and its run
#   record shows up in the list
# - excluded / unknown id -> 404; limit out of range -> 422
#
# Run: tests/lanes/run --only try/integration/api/colonel/chores_try.rb

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

def get(*args);    @test.get(*args);               end
def post(*args);   @test.post(*with_csrf(args));   end
def last_response; @test.last_response;            end
def body;          JSON.parse(last_response.body); end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_chores_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_chores_#{@timestamp}@example.com")
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

@json = { 'HTTP_ACCEPT' => 'application/json' }

@preview_chore = 'housekeeping.organization.standardize_planid'
@live_chore    = 'housekeeping.customer.reserialize_fields'
@run_keys      = [@preview_chore, @live_chore].map { |id| Onetime::Jobs::JobRun.key("chore.#{id}") }
Familia.dbclient.del(*@run_keys)

def run_chore(id, payload, confirm: nil)
  env = { 'rack.session' => @colonel_session, 'CONTENT_TYPE' => 'application/json' }.merge(@json)
  env['HTTP_X_OTS_CONFIRM'] = confirm if confirm
  post "/api/colonel/chores/#{id}/run", JSON.generate(payload), env
end

def chore_row(id)
  get '/api/colonel/chores', {}, { 'rack.session' => @colonel_session }.merge(@json)
  body['details']['chores'].find { |row| row['id'] == id }
end

# TRYOUTS

## Anonymous (no session) gets 401
@test.clear_cookies
get '/api/colonel/chores', {}, @json
last_response.status
#=> 401

## Non-colonel gets 403
get '/api/colonel/chores', {}, { 'rack.session' => @regular_session }.merge(@json)
last_response.status
#=> 403

## Colonel gets the catalog, one row per chore id
get '/api/colonel/chores', {}, { 'rack.session' => @colonel_session }.merge(@json)
ids = body['details']['chores'].map { |row| row['id'] }
[last_response.status, ids == Onetime::Operations::Chores::Catalog.all.map(&:id)]
#=> [200, true]

## The vhost cleanup is not listed
body['details']['chores'].none? { |row| row['id'].end_with?('remove_orphaned_approximated_vhosts') }
#=> true

## A housekeeping dry run needs no confirmation and reports what a run would scan
run_chore(@preview_chore, { dry_run: true, limit: 10 })
[last_response.status, body['record'].values_at('chore', 'status', 'dry_run', 'limit'),
  body['details']['report']['dry_run_supported']]
#=> [200, ['housekeeping.organization.standardize_planid', 'dry_run', true, 10], false]

## ...and writes no run record
Familia.dbclient.exists(Onetime::Jobs::JobRun.key("chore.#{@preview_chore}"))
#=> 0

## A live run without X-OTS-Confirm is refused, naming the chore field
run_chore(@live_chore, { dry_run: false, limit: 1 })
[last_response.status, body['error_code'], body['field']]
#=> [403, 'confirmation_required', 'chore']

## The excluded vhost cleanup is a 404 even when confirmed
excluded = 'housekeeping.custom_domain.remove_orphaned_approximated_vhosts'
run_chore(excluded, { dry_run: false, limit: 1 }, confirm: excluded)
last_response.status
#=> 404

## An unknown chore is a 404
run_chore('housekeeping.customer.no_such_chore', { dry_run: true })
last_response.status
#=> 404

## A limit above the server maximum is a 422
run_chore(@live_chore, { dry_run: true, limit: 5000 })
last_response.status
#=> 422

## A confirmed live run executes and reports its bounds
run_chore(@live_chore, { dry_run: false, limit: 1 }, confirm: @live_chore)
[last_response.status, body['record'].values_at('status', 'dry_run', 'limit', 'capped'),
  body['details']['report']['scanned'], body['details']['cli']]
#=> [200, ['success', false, 1, true], 1, 'bin/ots housekeeping run Onetime::Customer reserialize_fields']

## The live run's record shows up in the list
chore_row(@live_chore).values_at('last_status', 'run_count')
#=> ['success', 1]

# TEARDOWN

Familia.dbclient.del(*@run_keys)
@colonel.destroy! if @colonel&.exists?
@regular.destroy! if @regular&.exists?
