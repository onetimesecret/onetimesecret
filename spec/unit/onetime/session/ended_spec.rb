# spec/unit/onetime/session/ended_spec.rb
#
# frozen_string_literal: true

# The ended-marker's key and its two failure rules (RISK-2026-09-19-01). The
# race it closes is driven through real requests in
# spec/integration/simple/logout_write_back_spec.rb.

require 'spec_helper'
require 'securerandom'
require 'onetime/session/ended'
require 'onetime/session/snapshot_ordering'
require 'onetime/models/session_metadata'
require 'onetime/operations/sessions/store'

RSpec.describe Onetime::SessionEnded do
  let(:sid) { SecureRandom.hex(32) }
  let(:db) { instance_double(Redis) }

  before { allow(OT).to receive(:global_secret).and_return('session-ended-spec-secret') }

  describe '.key_for' do
    it 'is the documented full-length HMAC-SHA256 under its own prefix' do
      digest = OpenSSL::HMAC.hexdigest('sha256', 'session-ended-spec-secret', "session-ended:v1:#{sid}")

      expect(described_class.key_for(sid)).to eq("ended_sid:#{digest}")
    end

    it 'accepts a Rack SessionId' do
      expect(described_class.key_for(Rack::Session::SessionId.new(sid))).to eq(described_class.key_for(sid))
    end

    it 'never contains the session id, in whole or in part' do
      key = described_class.key_for(sid)

      (0..(sid.length - 8)).each { |i| expect(key).not_to include(sid[i, 8]) }
    end

    it 'is domain-separated from the revoke handle and the snapshot epoch' do
      key = described_class.key_for(sid)

      expect(key).not_to include(Onetime::SessionMetadata.handle_for(sid))
      expect(key).not_to include(Onetime::SnapshotOrdering.epoch_for(sid))
    end

    # The session operations list every string key matching this pattern as a
    # session; a marker must never be one of them.
    it 'is outside the session scan pattern' do
      pattern = Onetime::Operations::Sessions::Store::SESSION_SCAN_PATTERN

      expect(File.fnmatch?(pattern, described_class.key_for(sid))).to be(false)
    end

    it 'is nil for a blank id' do
      expect(described_class.key_for(nil)).to be_nil
      expect(described_class.key_for('')).to be_nil
    end
  end

  describe '.mark' do
    it 'sets the marker with the bounded TTL' do
      expect(db).to receive(:set).with(described_class.key_for(sid), '1', ex: described_class::TTL)

      expect(described_class.mark(sid, dbclient: db)).to be(true)
    end

    it 'is bounded by request duration, not by the session lifetime' do
      expect(described_class::TTL).to be_between(60, 600)
    end

    it 'never raises: the session must still be ended when the marker cannot be written' do
      allow(db).to receive(:set).and_raise(Redis::CannotConnectError)
      allow(OT).to receive(:lw)

      expect(described_class.mark(sid, dbclient: db)).to be(false)
      expect(OT).to have_received(:lw).with(satisfy { |line| !line.include?(sid) })
    end

    it 'writes nothing for a blank id' do
      expect(described_class.mark(nil, dbclient: db)).to be(false)
    end
  end

  describe '.ended?' do
    it 'is one EXISTS' do
      expect(db).to receive(:exists).with(described_class.key_for(sid)).once.and_return(1)

      expect(described_class.ended?(sid, dbclient: db)).to be(true)
    end

    it 'is false when the marker is absent' do
      allow(db).to receive(:exists).and_return(0)

      expect(described_class.ended?(sid, dbclient: db)).to be(false)
    end

    it 'raises on a datastore error: an unchecked write is not reported as saved' do
      allow(db).to receive(:exists).and_raise(Redis::CannotConnectError)

      expect { described_class.ended?(sid, dbclient: db) }.to raise_error(Redis::CannotConnectError)
    end
  end

  describe 'Onetime::Operations::Sessions::Store.destroy_blob' do
    it 'sets the marker before it deletes the blob' do
      key = "session:#{sid}"
      expect(db).to receive(:set).with(described_class.key_for(sid), '1', ex: described_class::TTL).ordered
      expect(db).to receive(:del).with(key).ordered.and_return(1)

      expect(Onetime::Operations::Sessions::Store.destroy_blob(db, key)).to eq(1)
    end

    it 'is the only blob delete in the session operations' do
      sources = Dir[File.join(Onetime::HOME, 'lib/onetime/operations/sessions/*.rb')]
      bare    = sources.reject { |path| path.end_with?('/store.rb') }
        .select { |path| File.read(path).match?(/^\s*(db|dbclient|redis)\.(del|unlink)\(/) }

      expect(bare).to be_empty
    end
  end
end
