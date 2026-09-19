# spec/unit/onetime/session/snapshot_ordering_spec.rb
#
# frozen_string_literal: true

# ADR-046 "Allocation": epoch derivation, the ordered-session rule, and the
# guard that keeps snapshot_generated_at out of every ordering decision. The
# counter itself is covered against real Valkey in
# try/unit/session/sidecar_try.rb.

require 'spec_helper'
require 'securerandom'
require 'onetime/session/snapshot_ordering'
require 'onetime/models/session_metadata'

RSpec.describe Onetime::SnapshotOrdering do
  let(:sid) { SecureRandom.hex(32) }
  let(:other_sid) { SecureRandom.hex(32) }

  before { allow(OT).to receive(:global_secret).and_return('snapshot-ordering-spec-secret') }

  describe '.epoch_for' do
    it 'is 32 lowercase hexadecimal characters' do
      expect(described_class.epoch_for(sid)).to match(/\A[0-9a-f]{32}\z/)
    end

    it 'is stable for one session id under an unchanged application secret' do
      expect(described_class.epoch_for(sid)).to eq(described_class.epoch_for(sid))
    end

    it 'changes when the session id is renewed' do
      expect(described_class.epoch_for(sid)).not_to eq(described_class.epoch_for(other_sid))
    end

    it 'changes when the application secret is rotated' do
      before_rotation = described_class.epoch_for(sid)
      allow(OT).to receive(:global_secret).and_return('rotated-secret')

      expect(described_class.epoch_for(sid)).not_to eq(before_rotation)
    end

    it 'never contains the session id, in whole or in part' do
      epoch = described_class.epoch_for(sid)

      expect(epoch).not_to eq(sid[0, 32])
      expect(sid).not_to include(epoch)
      (0..(sid.length - 8)).each { |i| expect(epoch).not_to include(sid[i, 8]) }
    end

    # The revoke endpoint accepts SessionMetadata.handle_for as an identifier.
    # The epoch is published to the tab; it must not be that handle.
    it 'is domain-separated from the colonel-facing revoke handle' do
      expect(described_class::EPOCH_DOMAIN).not_to eq(Onetime::SessionMetadata::HANDLE_DOMAIN)
      expect(described_class.epoch_for(sid)).not_to eq(Onetime::SessionMetadata.handle_for(sid))
    end

    it 'is the documented HMAC-SHA256 truncation' do
      expected = OpenSSL::HMAC.hexdigest(
        'sha256', 'snapshot-ordering-spec-secret', "bootstrap-snapshot-epoch:v1:#{sid}"
      )[0, 32]

      expect(described_class.epoch_for(sid)).to eq(expected)
    end
  end

  describe '.ordered?' do
    it 'orders an authenticated session' do
      expect(described_class.ordered?({ 'authenticated' => true })).to be(true)
    end

    it 'orders an MFA-pending session (awaiting_mfa is sidecar-merged into the loaded hash)' do
      expect(described_class.ordered?({ 'awaiting_mfa' => true })).to be(true)
    end

    it 'does not order an anonymous session, or anything that is not strictly true' do
      [nil, {}, { 'csrf' => 'x' }, { 'authenticated' => false }, { 'authenticated' => 'true' },
       { 'awaiting_mfa' => 1 }, 'not a session'].each do |session|
        expect(described_class.ordered?(session)).to be(false)
      end
    end
  end

  describe '.allocate' do
    let(:session) { double('session', id: double('sid', public_id: sid)) }

    before do
      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_return('1758236400000001')
    end

    it 'returns the epoch, the version as a string, and a fixed-width UTC timestamp' do
      result = described_class.allocate(session, ttl: 3600)

      expect(result.keys).to contain_exactly(:epoch, :version, :generated_at)
      expect(result[:epoch]).to eq(described_class.epoch_for(sid))
      expect(result[:version]).to eq('1758236400000001')
      expect(result[:generated_at]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z\z/)
    end

    it 'allocates on the counter field with the session lifetime it was given' do
      described_class.allocate(session, ttl: 3600)

      expect(Onetime::SessionSidecar).to have_received(:allocate_counter).with(sid, 'snapshot_version', ttl: 3600)
    end

    it 'never puts the session id in its result' do
      expect(described_class.allocate(session).to_s).not_to include(sid)
    end

    it 'raises rather than returning an unversioned result' do
      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_raise(Redis::CannotConnectError)

      expect { described_class.allocate(session) }.to raise_error(Redis::CannotConnectError)
    end

    it 'raises for a session without a usable id' do
      allow(Onetime::SessionSidecar).to receive(:allocate_counter).and_call_original

      expect { described_class.allocate(double('session', id: nil)) }
        .to raise_error(Onetime::SessionSidecar::CounterAllocationError)
    end
  end

  # ADR-046: snapshot_generated_at orders nothing, on the server or in the
  # schema. It may be produced, passed through and documented; nothing may
  # branch on it. This pins the set of files that mention it at all, so a new
  # reader has to be added here, in view of this rule.
  describe 'snapshot_generated_at is never an ordering input' do
    let(:roots) { %w[lib apps src/schemas src/shared src/services src/plugins src/router src/utils] }

    let(:mentions) do
      roots.flat_map { |root| Dir.glob(File.join(Onetime::HOME, root, '**', '*.{rb,ts,vue}')) }
        .reject { |path| path.include?('/spec/') || path.include?('/tests/') }
        .select { |path| File.read(path).match?(/snapshot_generated_at|generated_at:|\[:generated_at\]/) }
        .map { |path| path.delete_prefix("#{Onetime::HOME}/") }
        .select { |path| File.read(File.join(Onetime::HOME, path)).include?('snapshot') }
    end

    it 'is mentioned only by the allocator, the serializer and the schema' do
      expect(mentions).to contain_exactly(
        'lib/onetime/session/snapshot_ordering.rb',
        'apps/web/core/views/serializers/system_serializer.rb',
        'src/schemas/contracts/bootstrap.ts',
      )
    end

    it 'has no format constraint inside bootstrapSchema' do
      source = File.read(File.join(Onetime::HOME, 'src/schemas/contracts/bootstrap.ts'))

      expect(source).to match(/^\s*snapshot_generated_at: z\.string\(\)\.optional\(\),$/)
    end

    it 'is not compared or branched on by the serializer' do
      source = File.read(File.join(Onetime::HOME, 'apps/web/core/views/serializers/system_serializer.rb'))
      lines  = source.lines.grep(/generated_at/).reject { |line| line.strip.start_with?('#') }
      # Hash rockets are not comparisons.
      code   = lines.map { |line| line.gsub('=>', '') }

      expect(code.grep(/[<>]|==|\bcase\b|\bunless\b/)).to be_empty
      # The one permitted conditional drops a nil timestamp; it gates only the
      # timestamp's own key, never the pair.
      expect(code.grep(/\bif\b/)).to contain_exactly(
        a_string_matching(/output\.delete\('snapshot_generated_at'\) if output\['snapshot_generated_at'\]\.nil\?/),
      )
    end
  end
end
