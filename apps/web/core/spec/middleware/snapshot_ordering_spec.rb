# apps/web/core/spec/middleware/snapshot_ordering_spec.rb
#
# frozen_string_literal: true

# ADR-046 "Server allocation": once per Web Core request that carries an
# ordered session, ahead of the router (and so the authentication strategy);
# nothing at all for an anonymous session; a failure recorded, never raised.
#
# Run: tests/lanes/run unit --only apps/web/core/spec/middleware/snapshot_ordering_spec.rb

require 'spec_helper'
require 'securerandom'

require_relative '../../middleware/snapshot_ordering'

RSpec.describe Core::Middleware::SnapshotOrdering do
  let(:env_key) { Onetime::SnapshotOrdering::ENV_KEY }
  let(:sid) { SecureRandom.hex(32) }
  let(:downstream_seen) { {} }

  # Stands in for the router + authentication strategy: records what the env
  # held at the moment the strategy would run.
  let(:downstream) do
    lambda do |env|
      downstream_seen[:ordering] = env[env_key]
      downstream_seen[:called]   = true
      [200, { 'content-type' => 'text/html' }, ['ok']]
    end
  end

  let(:middleware) { described_class.new(downstream) }

  def session_with(data)
    session = data.dup
    id      = double('sid', public_id: sid)
    session.define_singleton_method(:id) { id }
    session
  end

  def env_for(session_data, options: { expire_after: 7200 })
    {
      'rack.session' => session_with(session_data),
      'rack.session.options' => options,
      'HTTP_X_REQUEST_ID' => 'req-4457',
    }
  end

  before do
    allow(OT).to receive(:global_secret).and_return('snapshot-ordering-mw-secret')
    allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_return('1758236400000042')
  end

  describe 'an ordered session' do
    it 'allocates before the downstream app (the strategy) runs' do
      env = env_for({ 'authenticated' => true })

      middleware.call(env)

      expect(downstream_seen[:ordering]).to include(
        epoch: Onetime::SnapshotOrdering.epoch_for(sid),
        version: '1758236400000042',
      )
    end

    it 'allocates for an MFA-pending session too' do
      middleware.call(env_for({ 'awaiting_mfa' => true }))

      expect(downstream_seen[:ordering]).to include(version: '1758236400000042')
    end

    it 'allocates exactly once per request' do
      middleware.call(env_for({ 'authenticated' => true }))

      expect(Onetime::SessionSidecar).to have_received(:allocate_counter).once
    end

    it 'hands the allocator the lifetime the session commit will write, not a remaining TTL' do
      middleware.call(env_for({ 'authenticated' => true }))

      expect(Onetime::SessionSidecar).to have_received(:allocate_counter)
        .with(sid, 'snapshot_version', ttl: 7200)
    end

    it 'returns the downstream response untouched' do
      response = middleware.call(env_for({ 'authenticated' => true }))

      expect(response).to eq([200, { 'content-type' => 'text/html' }, ['ok']])
    end
  end

  describe 'an anonymous session' do
    it 'allocates nothing, touches no Redis key, and sets no env key' do
      [{}, { 'csrf' => 'token' }, { 'authenticated' => false }].each do |data|
        env = env_for(data)
        middleware.call(env)

        expect(env).not_to have_key(env_key)
      end
      expect(Onetime::SessionSidecar).not_to have_received(:allocate_counter)
      expect(downstream_seen[:called]).to be(true)
    end

    it 'passes a request with no session at all' do
      env = {}

      expect(middleware.call(env).first).to eq(200)
      expect(env).not_to have_key(env_key)
    end
  end

  describe 'allocation failure' do
    let(:logger) { spy('session_logger') }

    before do
      allow(Onetime).to receive(:session_logger).and_return(logger)
      allow(Onetime::SessionSidecar).to receive(:allocate_counter)
        .and_raise(Redis::CannotConnectError, "Error connecting for key sidecar:#{sid}:snapshot_version")
    end

    it 'is recorded for the request and never raised: the request and its session write go on' do
      env      = env_for({ 'authenticated' => true })
      response = nil

      expect { response = middleware.call(env) }.not_to raise_error
      expect(response.first).to eq(200)
      expect(downstream_seen[:ordering]).to eq(error: 'Redis::CannotConnectError')
      expect(env['rack.session']).to eq('authenticated' => true)
    end

    it 'records a session id that fails the sidecar format guard the same way' do
      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_call_original
      env                 = env_for({ 'authenticated' => true })
      bad_id              = double('sid', public_id: 'not-a-valid-sid')
      env['rack.session'].define_singleton_method(:id) { bad_id }

      middleware.call(env)

      expect(env[env_key]).to eq(error: 'Onetime::SessionSidecar::CounterAllocationError')
    end

    it 'logs a diagnostic with the request id and error class, and never the session id' do
      middleware.call(env_for({ 'authenticated' => true }))

      expect(logger).to have_received(:warn) do |message, payload|
        expect(message).to eq('Snapshot ordering allocation failed')
        expect(payload).to eq(module: 'SnapshotOrdering', error: 'Redis::CannotConnectError', request_id: 'req-4457')
        expect("#{message} #{payload}").not_to include(sid)
      end
    end

    it 'survives a logger that raises' do
      allow(logger).to receive(:warn).and_raise(IOError)

      expect { middleware.call(env_for({ 'authenticated' => true })) }.not_to raise_error
    end
  end
end
