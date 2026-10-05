# spec/unit/onetime/models/custom_domain/ownership_verification_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# Behavior specs live under the model directory rather than the constant-derived path.
# rubocop:disable-next RSpec/SpecFilePathFormat
RSpec.describe Onetime::CustomDomain do
  def hydrate(fields)
    described_class.send(:instantiate_from_hash, fields)
  end

  describe 'legacy field compatibility' do
    [true, false, 'true', 'false', 'yes', 1, 0].each do |value|
      it "coerces a legacy #{value.inspect} through the native boolean type" do
        domain   = hydrate('verified' => JSON.generate(value))
        expected = Onetime::Models::FieldTypes::BooleanFieldType.truthy?(value)

        expect([domain.ownership_verified, domain.verified]).to eq([expected, expected])
      end
    end

    it 'leaves ownership undetermined when neither field exists' do
      expect(hydrate({}).ownership_verified).to be_nil
    end

    it 'prefers canonical false over legacy true regardless of hash order' do
      [
        { 'verified' => 'true', 'ownership_verified' => 'false' },
        { 'ownership_verified' => 'false', 'verified' => 'true' },
      ].each do |fields|
        domain = hydrate(fields)
        expect([domain.ownership_verified, domain.verified]).to eq([false, false])
      end
    end

    it 'prefers canonical true over legacy false' do
      domain = hydrate('verified' => 'false', 'ownership_verified' => 'true')
      expect(domain.ownership_verified).to be(true)
    end

    it 'treats nil as unset, not as revocation' do
      domain = hydrate('verified' => 'true', 'ownership_verified' => 'null')
      states = [domain.ownership_verified]

      domain.ownership_verified = false
      states << domain.ownership_verified
      domain.ownership_verified = nil
      states << domain.ownership_verified

      expect(states).to eq([true, false, true])
    end

    it 'accepts the legacy constructor keyword without masking canonical false' do
      domain = described_class.new(verified: 'yes', ownership_verified: false)
      expect([domain.legacy_verified, domain.ownership_verified]).to eq([true, false])
    end

    it 'routes the legacy setter through canonical boolean coercion' do
      domain          = hydrate('verified' => 'true')
      domain.verified = 'no'

      expect([domain.ownership_verified, domain.legacy_verified]).to eq([false, true])
    end

    it 'does not access the datastore when reading ownership or lifecycle state' do
      domain   = hydrate('verified' => 'true', 'txt_validation_value' => '"challenge"', 'resolving' => 'true')
      allow(domain).to receive_messages(dbclient: instance_double(Redis), hget: nil)
      observed = [domain.ownership_verified, domain.verification_state]

      aggregate_failures do
        expect(observed).to eq([true, :verified])
        expect(domain).not_to have_received(:dbclient)
        expect(domain).not_to have_received(:hget)
      end
    end
  end

  describe 'persistence' do
    it 'only serializes the canonical storage field, including a fallback value' do
      domain  = hydrate('verified' => 'true')
      storage = domain.to_h_for_storage

      aggregate_failures do
        expect(storage['ownership_verified']).to eq('true')
        expect(storage).not_to have_key('verified')
        expect(described_class.persistent_fields).not_to include(:verified)
      end
    end

    it 'serializes revocation as canonical false rather than deleting the field' do
      domain          = hydrate('verified' => 'true')
      domain.verified = false
      expect(domain.to_h_for_storage['ownership_verified']).to eq('false')
    end

    it 'routes legacy fast writes to the canonical writer' do
      domain = hydrate('verified' => 'true')
      allow(domain).to receive(:ownership_verified!).with(false).and_return(true)
      result = domain.verified!(false)

      aggregate_failures do
        expect(result).to be(true)
        expect(domain).to have_received(:ownership_verified!).with(false).once
      end
    end

    it 'preserves the canonical fast reader signature and raw-byte result' do
      domain = hydrate({})
      allow(domain).to receive(:ownership_verified!).with(nil).and_return('false')
      result = domain.verified!(nil)

      aggregate_failures do
        expect(result).to eq('false')
        expect(domain).to have_received(:ownership_verified!).with(nil).once
      end
    end
  end

  describe '#save_fields' do
    let(:domain) { hydrate('verified' => 'true') }

    before do
      domain.verified = false
      allow(domain).to receive_messages(
        prepare_for_partial_write: [],
        auto_update_class_indexes: nil,
        touch_instances!: nil,
        persisted_successfully?: true,
        hmset: nil,
      )
      allow(domain).to receive(:transaction).and_yield(nil).and_return([true])
    end

    it 'maps legacy partial saves to the canonical field' do
      domain.save_fields('verified', :ownership_verified, update_expiration: false)

      expect(domain).to have_received(:hmset).with(ownership_verified: 'false').once
    end
  end

  describe '#refresh!' do
    let(:domain) { hydrate('ownership_verified' => 'true', 'verified' => 'true') }
    let(:connection) { instance_double(Redis, exists: true) }

    before do
      allow(domain).to receive_messages(dbclient: connection, dbkey: 'custom_domain:test:object')
    end

    it 'drops a removed canonical value and loads legacy false' do
      allow(domain).to receive(:hgetall).and_return('verified' => 'false')
      domain.refresh!
      expect(domain.ownership_verified).to be(false)
    end

    it 'clears both ownership values when both fields are absent' do
      allow(domain).to receive(:hgetall).and_return({})
      domain.refresh!
      expect(domain.ownership_verified).to be_nil
    end

    it 'restores canonical false without exposing legacy true when refresh fails' do
      domain.ownership_verified = false
      allow(domain).to receive(:hgetall).and_raise(Redis::CannotConnectError)
      aggregate_failures do
        expect { domain.refresh! }.to raise_error(Redis::CannotConnectError)
        expect(domain.ownership_verified).to be(false)
      end
    end
  end

  describe '#verification_state' do
    [
      [nil, false, false, :unverified],
      [nil, false, true, :unverified],
      [nil, true, false, :unverified],
      [nil, true, true, :unverified],
      ['challenge', false, false, :pending],
      ['challenge', false, true, :resolving],
      ['challenge', true, false, :pending],
      ['challenge', true, true, :verified],
    ].each do |challenge, ownership, resolving, expected|
      it "labels challenge=#{challenge.inspect}, ownership=#{ownership}, resolving=#{resolving} as #{expected}" do
        domain = described_class.new(
          txt_validation_value: challenge,
          ownership_verified: ownership,
          resolving: resolving,
        )

        expect([domain.verification_state, domain.ready?]).to eq([expected, expected == :verified])
      end
    end

    it 'leaves operator-verified ownership pending until the domain resolves' do
      domain = described_class.new(
        txt_validation_value: 'challenge',
        ownership_verified: true,
        verified_by_override: true,
        resolving: false,
      )
      expect([domain.ownership_verified, domain.verification_state, domain.ready?]).to eq([true, :pending, false])
    end
  end
end
