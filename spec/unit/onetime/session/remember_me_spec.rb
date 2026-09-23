# spec/unit/onetime/session/remember_me_spec.rb
#
# frozen_string_literal: true

# Onetime::RememberMe: parameter parsing and the deadline arithmetic the
# session store derives the blob TTL and cookie lifetime from. The store
# itself is exercised end to end in spec/integration/{simple,full}/remember_me_spec.rb.

require 'spec_helper'
require 'onetime/session/remember_me'

RSpec.describe Onetime::RememberMe do
  let(:now) { Time.at(1_800_000_000) }

  describe '.requested?' do
    it 'accepts exactly true, "true", "1" and "on"' do
      expect([true, 'true', '1', 'on'].map { |v| described_class.requested?(v) }).to all(be(true))
    end

    it 'refuses everything else' do
      values = [nil, false, 'false', '0', '', 'yes', 'TRUE', 'On', ' true', 1, [], {}, 'remember']
      expect(values.map { |v| described_class.requested?(v) }).to all(be(false))
    end
  end

  describe '.stamp' do
    it 'writes an integer epoch DURATION from now under the string key' do
      session = {}
      described_class.stamp(session, now: now)
      expect(session).to eq('remember_until' => now.to_i + described_class::DURATION)
    end
  end

  describe '.enabled?' do
    it 'follows the mode-independent switch' do
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)
      expect(described_class.enabled?).to be(false)
    end

    it 'is false, not an error, when the config cannot be read' do
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_raise(RuntimeError)
      expect(described_class.enabled?).to be(false)
    end
  end

  describe '.remaining' do
    before { allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(true) }

    it 'is nil for a stamped session once remember-me is switched off' do
      allow(Onetime.auth_config).to receive(:remember_me_sessions_enabled?).and_return(false)
      expect(described_class.remaining({ 'remember_until' => now.to_i + 3600 }, now: now)).to be_nil
    end

    it 'is the seconds left to the deadline' do
      expect(described_class.remaining({ 'remember_until' => now.to_i + 3600 }, now: now)).to eq(3600)
    end

    it 'is nil for a session that is not remembered' do
      expect(described_class.remaining({}, now: now)).to be_nil
      expect(described_class.remaining(nil, now: now)).to be_nil
    end

    it 'is nil once the deadline has passed' do
      expect(described_class.remaining({ 'remember_until' => now.to_i }, now: now)).to be_nil
      expect(described_class.remaining({ 'remember_until' => now.to_i - 1 }, now: now)).to be_nil
    end

    it 'is nil for a value that is not an integer epoch' do
      ['1800003600', 1_800_003_600.0, true, [1]].each do |garbage|
        expect(described_class.remaining({ 'remember_until' => garbage }, now: now)).to be_nil
      end
    end

    it 'never exceeds DURATION, whatever is stored' do
      far = { 'remember_until' => now.to_i + (described_class::DURATION * 100) }
      expect(described_class.remaining(far, now: now)).to eq(described_class::DURATION)
    end
  end
end
