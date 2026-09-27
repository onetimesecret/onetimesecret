# spec/integration/full/bootstrap_snapshot_ordering_spec.rb
#
# frozen_string_literal: true

# ADR-046, server half (#4457), through the real stack: the session store,
# Core::Middleware::SnapshotOrdering, the authentication strategy, the
# serializers and both delivery paths (HTML hydration and GET /bootstrap/me).
#
# The counter's own properties (seeding, atomicity, TTL, reseeding) are covered
# against real Valkey in try/unit/session/sidecar_try.rb; the per-state
# presence/absence of the pair is covered by the failure matrix. This file
# covers what only a whole request can show.

require 'spec_helper'
require_relative '../../support/customer_session_failure_matrix'

RSpec.describe 'Bootstrap snapshot ordering (ADR-046, #4457)', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Matrix-Test1234!' }
  let(:counter_key) { Onetime::SessionSidecar.key_for(current_session_id, 'snapshot_version') }

  before { @matrix_customer = anonymous_probe_customer }

  def snapshot(surface)
    request_surface(surface, request_id: "ordering-#{surface}-#{SecureRandom.hex(4)}")
  end

  def fail_allocation!
    allow(Onetime::SessionSidecar).to receive(:allocate_counter)
      .and_raise(Redis::CannotConnectError, 'snapshot ordering spec: simulated Redis failure')
  end

  describe 'an authenticated session' do
    before { establish_matrix_session! }

    it 'carries one stream across both delivery paths: a stable epoch and a strictly increasing version' do
      observations = [snapshot(:bootstrap), snapshot(:hydrated_html), snapshot(:bootstrap), snapshot(:hydrated_html)]

      expect(observations.map { |o| o[:snapshot_epoch] }.uniq.size).to eq(1)
      versions = observations.map { |o| Integer(o[:snapshot_version]) }
      expect(versions.each_cons(2)).to all(satisfy { |earlier, later| later > earlier })
    end

    it 'derives the epoch from the session id without exposing it' do
      observation = snapshot(:bootstrap)

      expect(observation[:snapshot_epoch]).to eq(Onetime::SnapshotOrdering.epoch_for(current_session_id))
      expect(observation[:session_id_exposed]).to be(false)
      expect(observation[:snapshot_epoch]).not_to eq(Onetime::SessionMetadata.handle_for(current_session_id))
    end

    it 'sends the version as a JSON string, never a number' do
      snapshot(:bootstrap)

      expect(last_response.body).to match(/"snapshot_version":"[1-9][0-9]*"/)
    end

    it 'sends snapshot_generated_at in the fixed-width UTC format' do
      payload = snapshot(:bootstrap).fetch(:payload)

      expect(payload['snapshot_generated_at']).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
    end

    it 'keeps the counter on the session lifetime, not a remaining TTL' do
      snapshot(:bootstrap)

      expire_after = Onetime.session_config['expire_after'].to_i
      expect(Familia.dbclient.ttl(counter_key)).to be_between(expire_after - 30, expire_after)
    end

    it 'allocates ahead of the authentication strategy (the version is a start stamp)' do
      seen = []
      [Onetime::Application::AuthStrategies::NoAuthStrategy,
       Onetime::Application::AuthStrategies::SessionAuthStrategy].each do |strategy|
        allow_any_instance_of(strategy).to receive(:authenticate).and_wrap_original do |original, env, *rest|
          seen << env[Onetime::SnapshotOrdering::ENV_KEY]&.dup
          original.call(env, *rest)
        end
      end

      observation = snapshot(:bootstrap)

      expect(seen).not_to be_empty
      expect(seen.first).to include(version: observation[:snapshot_version], epoch: observation[:snapshot_epoch])
    end

    it 'survives the loss of the counter key inside a live session: the reseeded version is still greater' do
      before_loss = Integer(snapshot(:bootstrap)[:snapshot_version])
      Familia.dbclient.del(counter_key)
      after_loss = snapshot(:bootstrap)

      expect(Integer(after_loss[:snapshot_version])).to be > before_loss
      expect(after_loss[:snapshot_epoch]).to eq(Onetime::SnapshotOrdering.epoch_for(current_session_id))
    end

    it 'starts a new epoch when the session id is renewed, and purges the old counter' do
      first     = snapshot(:bootstrap)
      old_key   = counter_key
      post_json '/auth/logout', {}
      expect(Familia.dbclient.exists(old_key)).to eq(0)

      post_json '/auth/login', { login: @matrix_email, password: matrix_password }
      expect(last_response.status).to eq(200)
      second = snapshot(:bootstrap)

      expect(second[:snapshot_epoch]).to match(/\A[0-9a-f]{32}\z/)
      expect(second[:snapshot_epoch]).not_to eq(first[:snapshot_epoch])
    end
  end

  describe 'an anonymous session' do
    it 'allocates nothing: no fields on either path and no Redis key' do
      clear_cookies
      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_call_original

      bootstrap = snapshot(:bootstrap)
      hydrated  = snapshot(:hydrated_html)

      expect(bootstrap[:snapshot_keys]).to eq([])
      expect(hydrated[:snapshot_keys]).to eq([])
      expect(Onetime::SessionSidecar).not_to have_received(:allocate_counter)
      # The anonymous request did persist a (CSRF-bearing) session; it has no
      # counter beside it.
      expect(current_session_id.to_s).not_to be_empty
      expect(Familia.dbclient.exists(counter_key)).to eq(0)
    end
  end

  describe 'allocation failure' do
    before { establish_matrix_session! }

    it 'answers GET /bootstrap/me with a retryable, unstorable 503 and no snapshot', :aggregate_failures do
      fail_allocation!

      get '/bootstrap/me', {}, { 'HTTP_ACCEPT' => 'application/json' }

      expect(last_response.status).to eq(503)
      expect(last_response.headers['retry-after']).to eq('5')
      expect(last_response.headers['cache-control']).to eq('private, no-store')
      body = JSON.parse(last_response.body)
      expect(body).to include(
        'error' => 'Snapshot ordering unavailable',
        'error_type' => 'SnapshotOrderingUnavailable',
        'retry_after' => 5,
      )
      expect(body.keys).not_to include('cust', 'authenticated', 'auth_status', 'snapshot_epoch')
      expect(last_response.body).not_to include(@matrix_customer.email)
    end

    it 'still renders hydrated HTML, reporting the session without the pair (degraded hydration)', :aggregate_failures do
      fail_allocation!

      observation = snapshot(:hydrated_html)

      expect(observation[:status]).to eq(200)
      expect(observation).to include(auth_status: 'authenticated', authenticated: true, customer_exposed: true)
      expect(observation[:snapshot_keys]).to eq([])
    end

    it 'never fails the session write: the session survives and the next request is ordered again' do
      sid = current_session_id
      fail_allocation!
      get '/bootstrap/me', {}, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(503)

      expect(current_session_id).to eq(sid)
      expect(session_store.find_key(Familia.dbclient, sid)).not_to be_nil

      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_call_original
      recovered = snapshot(:bootstrap)
      expect(recovered).to include(status: 200, auth_status: 'authenticated')
      expect(recovered[:snapshot_version]).to match(/\A[1-9][0-9]*\z/)
    end

    it 'does not touch a route that serializes no snapshot' do
      fail_allocation!

      observation = snapshot(:protected_api)

      expect(observation[:status]).to eq(200)
    end

    # The rule that matters most: an ordering outage must never be able to
    # withhold the end of a session from the tab.
    it 'still delivers a revoked session as a plain anonymous snapshot, not a 503', :aggregate_failures do
      active_session_rows.delete
      fail_allocation!

      observation = snapshot(:bootstrap)

      expect(observation[:status]).to eq(200)
      expect(observation).to include(auth_status: 'anonymous', authenticated: false, customer_exposed: false)
      expect(observation[:snapshot_keys]).to eq([])
    end
  end

  describe 'session end still reaches the client with ordering live' do
    before { establish_matrix_session! }

    it 'server-side revocation: an ordered stream is followed by an unordered anonymous snapshot' do
      expect(snapshot(:bootstrap)[:snapshot_version]).not_to be_nil

      active_session_rows.delete
      ended = snapshot(:bootstrap)

      expect(ended).to include(status: 200, auth_status: 'anonymous', authenticated: false)
      expect(ended[:snapshot_keys]).to eq([])
    end

    it 'session expiry: the inactivity deadline ends the stream the same way' do
      expect(snapshot(:bootstrap)[:snapshot_version]).not_to be_nil

      active_session_rows.update(last_use: Time.now - (Onetime::ActiveSessionGate::INACTIVITY_DEADLINE + 60))
      ended = snapshot(:hydrated_html)

      expect(ended).to include(status: 200, auth_status: 'anonymous', authenticated: false)
      expect(ended[:snapshot_keys]).to eq([])
    end
  end
end
