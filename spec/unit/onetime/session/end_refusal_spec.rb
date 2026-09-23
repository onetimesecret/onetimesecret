# spec/unit/onetime/session/end_refusal_spec.rb
#
# frozen_string_literal: true

# RISK-2026-09-19-01: three defects on the ended-marker invariant.
#
# 1) Store.destroy_blob: when SessionEnded.mark fails transiently, the DEL
#    must be REFUSED (marker+DEL are one atomic step in the invariant).
# 2) Session#delete_session: same contract on the Rack middleware path.
# 3) Session#write_session: when the post-SET SessionEnded.ended? check
#    raises (datastore error), the freshly-written blob must be deleted so
#    the browser cannot keep a working session under an already-ended sid.

require 'spec_helper'
require 'securerandom'
require 'onetime/session'
require 'onetime/session/ended'
require 'onetime/operations/sessions/store'

RSpec.describe 'Onetime::SessionEnded marker refusal contract' do
  let(:sid) { SecureRandom.hex(32) }
  let(:db) { instance_double(Redis) }

  before { allow(OT).to receive(:global_secret).and_return('end-refusal-spec-secret') }

  describe 'Onetime::Operations::Sessions::Store.destroy_blob' do
    it 'DELs the blob when the marker was written' do
      allow(db).to receive(:set)
        .with(Onetime::SessionEnded.key_for(sid), '1', ex: Onetime::SessionEnded::TTL)
      expect(db).to receive(:del).with("session:#{sid}").and_return(1)

      expect(Onetime::Operations::Sessions::Store.destroy_blob(db, "session:#{sid}")).to eq(1)
    end

    it 'refuses the DEL and returns nil when SessionEnded.mark raises internally' do
      allow(db).to receive(:set).and_raise(Redis::CannotConnectError)
      allow(OT).to receive(:lw)

      expect(db).not_to receive(:del)
      expect(Onetime::Operations::Sessions::Store.destroy_blob(db, "session:#{sid}")).to be_nil
    end
  end

  describe 'Onetime::Session#delete_session' do
    # Instantiate without going through initialize (which requires a secret /
    # site config): the method under test only reads @dbclient and calls
    # session_logger, both stubbed below.
    let(:session) do
      s = Onetime::Session.allocate
      s.instance_variable_set(:@dbclient, db)
      s.instance_variable_set(:@namespace, 'session')
      s.instance_variable_set(:@expire_after, 86_400)
      s
    end

    let(:logger) { instance_double(SemanticLogger::Logger, info: nil, error: nil, trace: nil, warn: nil, debug: nil) }

    before do
      allow(session).to receive(:session_logger).and_return(logger)
      allow(session).to receive(:generate_sid).and_return('new-sid')
      # SessionMetadata.load hits the datastore in the tail cleanup;
      # short-circuit so this test is purely local.
      allow(Onetime::SessionMetadata).to receive(:load).and_return(nil)
      allow(Onetime::SessionSidecar).to receive(:purge)
      allow(Onetime::SessionSidecar).to receive(:inflight_fields).and_return([])
    end

    it 'refuses the blob DEL when the marker write fails' do
      allow(Onetime::SessionEnded).to receive(:mark).and_return(false)

      # The whole point: no DEL against the session blob.
      expect(db).not_to receive(:del)
      # And an error line naming the refusal so operators can see it.
      expect(logger).to receive(:error).with(
        'Session delete refused: ended-marker write failed',
        hash_including(operation: 'delete'),
      )

      session.send(:delete_session, nil, sid, {})
    end

    it 'deletes the blob when the marker was written' do
      allow(Onetime::SessionEnded).to receive(:mark).and_return(true)
      # Familia::StringKey#del is what runs — stub the whole chain:
      stringkey = instance_double(Familia::StringKey, del: 1)
      allow(session).to receive(:get_stringkey).and_return(stringkey)

      expect(stringkey).to receive(:del).and_return(1)
      session.send(:delete_session, nil, sid, {})
    end
  end

  describe 'Onetime::Session#write_session' do
    let(:session) do
      s = Onetime::Session.allocate
      s.instance_variable_set(:@dbclient, db)
      s.instance_variable_set(:@namespace, 'session')
      s.instance_variable_set(:@expire_after, 86_400)
      # Stub crypto helpers so we don't need @secret / @codec set up.
      allow(s).to receive(:encrypt_data) { |json| json }
      allow(s).to receive(:compute_hmac).and_return('deadbeef')
      allow(s).to receive(:expiration_for_write).and_return(86_400)
      s
    end

    let(:logger) { instance_double(SemanticLogger::Logger, info: nil, error: nil, trace: nil, warn: nil, debug: nil) }
    let(:stringkey) { instance_double(Familia::StringKey) }
    let(:request) { instance_double('Rack::Request', respond_to?: false) }

    before do
      allow(session).to receive(:session_logger).and_return(logger)
      allow(session).to receive(:get_stringkey).and_return(stringkey)
      allow(stringkey).to receive(:set)
      allow(stringkey).to receive(:update_expiration)
      allow(stringkey).to receive(:del)
      allow(Onetime::SessionSidecar).to receive(:commit) { |_sid, data, **_kw| data }
      allow(Onetime::SessionSidecar).to receive(:purge)
    end

    it 'deletes the freshly-written blob when SessionEnded.ended? raises AFTER the SET' do
      allow(Onetime::SessionEnded).to receive(:ended?).and_raise(Redis::CannotConnectError)

      # SET runs first (the exception is raised AFTER it), then the outer
      # rescue MUST compensate.
      expect(stringkey).to receive(:set).ordered
      expect(stringkey).to receive(:del).ordered
      expect(Onetime::SessionSidecar).to receive(:purge).with(sid, dbclient: db).ordered
      expect(logger).to receive(:info).with(
        'Session write failed; compensating delete attempted',
        hash_including(operation: 'write'),
      )

      expect(session.send(:write_session, request, sid, { 'account_id' => 1 }, {})).to be(false)
    end

    it 'does NOT compensate when the exception is raised BEFORE the SET' do
      allow(session).to receive(:encrypt_data).and_raise(RuntimeError, 'boom')

      expect(stringkey).not_to receive(:set)
      expect(stringkey).not_to receive(:del)
      expect(Onetime::SessionSidecar).not_to receive(:purge)

      expect(session.send(:write_session, request, sid, { 'account_id' => 1 }, {})).to be(false)
    end

    it 'a cleanup failure does not mask the original error and still returns false' do
      allow(Onetime::SessionEnded).to receive(:ended?).and_raise(Redis::CannotConnectError)
      allow(stringkey).to receive(:del).and_raise(Redis::CannotConnectError)

      expect(logger).to receive(:error).with('Error writing session', anything)
      expect(logger).to receive(:error).with(
        'Session write compensating delete failed',
        hash_including(operation: 'write'),
      )

      expect(session.send(:write_session, request, sid, { 'account_id' => 1 }, {})).to be(false)
    end
  end
end
