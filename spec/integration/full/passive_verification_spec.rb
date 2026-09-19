# spec/integration/full/passive_verification_spec.rb
#
# frozen_string_literal: true

# #4455: passive verification is separate from session activity.
#
# One example per acceptance criterion, through the whole stack in full auth
# mode. A signed-in session has three inactivity clocks, and each is asserted:
#
#   last_use          the active-session row (Rodauth's inactivity deadline)
#   last_activity_at  the SessionMetadata sidecar (the admin-surface idle bound)
#   the blob's TTL    the Rack session in Redis
#
# "Controlled clock" means the stored timestamps are moved, never Time.now.
# ActiveSessionGate decides against the database's CURRENT_TIMESTAMP, so
# stubbing Ruby's clock would prove nothing; back-dating `last_use` by an hour
# is what an hour of inactivity looks like to the code under test.
#
# "A passive check followed by a real activity in one request" cannot be
# produced over HTTP: passive is a property of the matched route. It is covered
# where it can be driven, in spec/unit/onetime/session/active_session_gate_spec.rb
# and customer_session_evaluator_spec.rb.

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Passive verification does not count as session activity (#4455)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Passive-Test1234!' }
  let(:gate) { Onetime::ActiveSessionGate }

  before do
    @matrix_customer = anonymous_probe_customer
    establish_matrix_session! # leaves last_use stale enough that a refresh is due
  end

  def poll(request_id: 'passive-poll')
    request_surface(:bootstrap, request_id: request_id)
  end

  def act(request_id: 'passive-activity')
    request_surface(:protected_api, request_id: request_id)
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

  def backdate_last_activity!(seconds)
    record                  = session_metadata
    record.last_activity_at = Familia.now.to_i - seconds
    record.save
    record.last_activity_at.to_i
  end

  it 'cannot extend inactivity by polling alone', :aggregate_failures do
    stale_last_use  = activity_snapshot.fetch(:last_use)
    stale_activity  = backdate_last_activity!(7_200)
    Familia.dbclient.expire(blob_key, 600)

    observations, writes = capture_activity_writes { Array.new(5) { |i| poll(request_id: "passive-poll-#{i}") } }

    expect(observations.map { |o| o[:auth_status] }).to all(eq('authenticated'))
    expect(writes).to be_empty
    expect(activity_snapshot.fetch(:last_use)).to eq(stale_last_use)
    expect(session_metadata.last_activity_at.to_i).to eq(stale_activity)
    expect(blob_ttl).to be <= 600

    # With nothing but polls behind it, the session reaches the deadline, and
    # the poll that finds it there reports the sign-out and removes the row.
    active_session_rows.update(last_use: Time.now - (gate::INACTIVITY_DEADLINE + 60))

    expect(poll(request_id: 'passive-poll-expired')).to include(status: 200, auth_status: 'anonymous', authenticated: false)
    expect(activity_count).to eq(0)
  end

  it 'still advances every clock for real activity', :aggregate_failures do
    stale_last_use = activity_snapshot.fetch(:last_use)
    stale_activity = backdate_last_activity!(7_200)
    Familia.dbclient.expire(blob_key, 600)
    poll

    observation, writes = capture_activity_writes { act }

    expect(observation[:status]).to eq(200)
    expect(writes.grep(/\bUPDATE\b/i)).not_to be_empty
    expect(activity_snapshot.fetch(:last_use)).to be > stale_last_use
    expect(session_metadata.last_activity_at.to_i).to be > stale_activity
    expect(blob_ttl).to be > 600
  end

  it 'counts a page load as activity: a person asked for it' do
    stale_last_use = activity_snapshot.fetch(:last_use)

    expect(request_surface(:hydrated_html, request_id: 'passive-page-load')).to include(status: 200, authenticated: true)
    expect(activity_snapshot.fetch(:last_use)).to be > stale_last_use
  end

  it 'holds the absolute lifetime whatever the activity', :aggregate_failures do
    expect(act[:status]).to eq(200)
    active_session_rows.update(created_at: Time.now - (gate::LIFETIME_DEADLINE + 60), last_use: Time.now)

    expect(act(request_id: 'passive-lifetime-api')).to include(status: 401, refusal_code: 'active_session_revoked')
    expect(activity_count).to eq(0)
    expect(poll(request_id: 'passive-lifetime-poll')).to include(status: 200, auth_status: 'anonymous')
  end

  it 'does not let a rejected request revive or extend the session', :aggregate_failures do
    stale_last_use = activity_snapshot.fetch(:last_use)
    stale_activity = backdate_last_activity!(7_200)
    Familia.dbclient.expire(blob_key, 600)
    @matrix_customer.suspended = 'true'
    @matrix_customer.save

    observation, writes = capture_activity_writes { act(request_id: 'passive-rejected') }

    expect(observation).to include(status: 401, refusal_code: 'account_suspended')
    expect(writes).to be_empty
    expect(activity_snapshot.fetch(:last_use)).to eq(stale_last_use)
    expect(session_metadata.last_activity_at.to_i).to eq(stale_activity)
    expect(blob_ttl).to be <= 600
  end

  it 'does not let a request refused during an authdb outage extend the session', :aggregate_failures do
    stale_activity = backdate_last_activity!(7_200)
    Familia.dbclient.expire(blob_key, 600)

    with_matrix_state_dependencies(:authentication_database_unavailable) do
      expect(act(request_id: 'passive-outage')).to include(status: 401, refusal_code: 'active_session_unavailable')
    end

    expect(session_metadata.last_activity_at.to_i).to eq(stale_activity)
    expect(blob_ttl).to be <= 600
  end

  it 'never revives an expired row, by a poll or by activity', :aggregate_failures do
    active_session_rows.update(last_use: Time.now - (gate::INACTIVITY_DEADLINE + 60))

    expect(act(request_id: 'passive-expired-api')).to include(status: 401, refusal_code: 'active_session_revoked')
    expect(activity_count).to eq(0)
    expect(poll(request_id: 'passive-expired-poll')).to include(auth_status: 'anonymous')
    expect(activity_count).to eq(0)
  end

  # The rollout review in #4463 reads this line; its counts are the ones the
  # SQL capture above sees, reported without a SQL logger.
  it 'reports what each poll cost, by request id and without a session identifier', :aggregate_failures do
    lines  = []
    logger = spy('session_logger')
    allow(logger).to receive(:info) { |message, payload| lines << [message, payload] }
    allow(Onetime).to receive(:get_logger).and_call_original
    allow(Onetime).to receive(:get_logger).with('Session').and_return(logger)
    allow(Onetime).to receive(:session_logger).and_return(logger)

    _observation, writes = capture_activity_writes { poll(request_id: 'passive-observed') }

    message, payload = lines.find { |line| line.first == 'Bootstrap verification' }
    expect(message).to eq('Bootstrap verification')
    expect(payload).to eq(
      passive: true,
      verdict: :authenticated,
      reason: :authenticated,
      active_session_queries: 1,
      active_session_writes: 0,
      request_id: 'passive-observed',
    )
    expect(writes.size).to eq(payload.fetch(:active_session_writes))
    expect(lines.inspect).not_to include(current_session_id)
  end
end
