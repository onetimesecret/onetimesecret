# spec/integration/simple/passive_verification_spec.rb
#
# frozen_string_literal: true

# #4455 in simple auth mode, the twin of
# spec/integration/full/passive_verification_spec.rb.
#
# Simple mode has no active-session table. The Rack session blob's TTL is the
# only inactivity clock there is, so "passive polling cannot extend inactivity"
# is a statement about that TTL and nothing else. The controlled clock is the
# key's own expiry, moved with EXPIRE.

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Passive verification does not count as session activity in simple mode (#4455)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Passive-Test1234!' }
  let(:app) do
    @simple_passive_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  before do
    skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?

    @matrix_customer = anonymous_probe_customer
    establish_simple_matrix_session!
  end

  def blob_key
    session_store.find_key(Familia.dbclient, current_session_id)
  end

  def blob_ttl
    Familia.dbclient.ttl(blob_key)
  end

  def session_metadata
    Onetime::SessionMetadata.load(current_session_id)
  end

  it 'does not grow the session TTL across polls, and lets it run out', :aggregate_failures do
    Familia.dbclient.expire(blob_key, 600)

    ttls = Array.new(5) do |i|
      observation = request_surface(:bootstrap, request_id: "simple-passive-poll-#{i}")
      expect(observation).to include(status: 200, auth_status: 'authenticated')
      blob_ttl
    end

    expect(ttls).to all(be <= 600)
    expect(ttls).to eq(ttls.sort.reverse)

    # Nothing but polls since: the blob expires on schedule, and the next poll
    # reports the sign-out.
    Familia.dbclient.del(blob_key)
    expect(request_surface(:bootstrap, request_id: 'simple-passive-poll-expired'))
      .to include(status: 200, auth_status: 'anonymous', authenticated: false)
  end

  it 'does not advance last_activity_at across polls' do
    record                  = session_metadata
    record.last_activity_at = Familia.now.to_i - 7_200
    record.save

    3.times { |i| request_surface(:bootstrap, request_id: "simple-passive-activity-#{i}") }

    expect(session_metadata.last_activity_at.to_i).to eq(record.last_activity_at.to_i)
  end

  it 'resets the session TTL for a real request', :aggregate_failures do
    Familia.dbclient.expire(blob_key, 600)
    request_surface(:bootstrap, request_id: 'simple-passive-before-activity')
    expect(blob_ttl).to be <= 600

    expect(request_surface(:protected_api, request_id: 'simple-passive-activity')[:status]).to eq(200)

    expect(blob_ttl).to be > 600
  end

  # RISK-2026-09-19-04: a timer-driven API request, declared passive by the
  # client. In simple mode the blob TTL is the whole inactivity clock.
  it 'does not grow the session TTL for a request the client declares passive', :aggregate_failures do
    Familia.dbclient.expire(blob_key, 600)

    ttls = Array.new(3) do |i|
      observation = request_surface(:protected_api, request_id: "simple-declared-passive-#{i}", declare_passive: true)
      expect(observation[:status]).to eq(200)
      blob_ttl
    end

    expect(ttls).to all(be <= 600)
  end

  it 'ignores the declaration on a state-changing request' do
    Familia.dbclient.expire(blob_key, 600)

    request_surface(:protected_api, request_id: 'simple-declared-passive-post', declare_passive: true, verb: :post)

    expect(blob_ttl).to be > 600
  end

  it 'resets the session TTL for a page load: a person asked for it' do
    Familia.dbclient.expire(blob_key, 600)

    expect(request_surface(:hydrated_html, request_id: 'simple-passive-page-load')).to include(status: 200, authenticated: true)

    expect(blob_ttl).to be > 600
  end

  it 'does not let a rejected request extend the session', :aggregate_failures do
    Familia.dbclient.expire(blob_key, 600)
    @matrix_customer.suspended = 'true'
    @matrix_customer.save

    expect(request_surface(:protected_api, request_id: 'simple-passive-rejected'))
      .to include(status: 401, refusal_code: 'account_suspended')

    expect(blob_ttl).to be <= 600
  end
end
