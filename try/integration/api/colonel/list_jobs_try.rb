# try/integration/api/colonel/list_jobs_try.rb
#
# frozen_string_literal: true

# Integration tests for the scheduler catalog endpoint (#4343):
#
#   GET /api/colonel/jobs
#
# Covers:
# - 401 for anonymous, 403 for non-colonel
# - 200 with one row per registered job class, the pagination envelope and
#   the scheduler record
# - a run record written by the scheduler shows up in its row
#
# The expected row count comes from the registry, not a hardcoded number:
# catalog_retry_job.rb defines its class only when billing is enabled, so the
# catalog has 16 rows with billing on and 15 without.
#
# Run: tests/lanes/run --only try/integration/api/colonel/list_jobs_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

require 'onetime/jobs/registry'
Onetime::Jobs::Registry.load_all!

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_jobs_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_jobs_#{@timestamp}@example.com")
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

@json            = { 'HTTP_ACCEPT' => 'application/json' }
@expected_ids    = Onetime::Jobs::Registry.entries.map { |entry| entry['job_id'] }.sort
@heartbeat_key   = Onetime::Jobs::JobRun.key('heartbeat')
Familia.dbclient.del(@heartbeat_key)

def heartbeat_row
  get '/api/colonel/jobs', {}, { 'rack.session' => @colonel_session }.merge(@json)
  JSON.parse(last_response.body)['details']['jobs'].find { |row| row['job_id'] == 'heartbeat' }
end

# TRYOUTS

## Anonymous (no session) gets 401
@test.clear_cookies
get '/api/colonel/jobs', {}, @json
last_response.status
#=> 401

## Non-colonel gets 403
get '/api/colonel/jobs', {}, { 'rack.session' => @regular_session }.merge(@json)
last_response.status
#=> 403

## Colonel gets 200 with one row per registered job class
get '/api/colonel/jobs', {}, { 'rack.session' => @colonel_session }.merge(@json)
@body = JSON.parse(last_response.body)
[last_response.status, @body['details']['jobs'].map { |row| row['job_id'] }.sort == @expected_ids]
#=> [200, true]

## The registry covers 15 or 16 job classes (billing-gated catalog_retry)
[15, 16].include?(@expected_ids.size)
#=> true

## The pagination envelope and the scheduler record are present
[@body['details']['pagination'].keys.sort, @body['record']['scheduler'].keys.sort]
#=> [%w[page per_page total_count total_pages], %w[alive heartbeat_at host job_count pid started_at]]

## A job with no run record reads as never run
heartbeat_row.values_at('last_status', 'run_count', 'error_count')
#=> ['never', 0, 0]

## A finished run shows up in the job's row
Onetime::Jobs::JobRun.finished('heartbeat', status: 'success', duration_ms: 5)
heartbeat_row.values_at('last_status', 'last_duration_ms', 'last_error')
#=> ['success', 5, nil]

# TEARDOWN

Familia.dbclient.del(@heartbeat_key)
