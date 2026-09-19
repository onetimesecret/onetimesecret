# spec/unit/onetime/security/saml_assertion_replay_guard_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/security/saml_assertion_replay_guard'

# Unit coverage for the SAML assertion replay cache (#4450). No datastore:
# the client is a double, so these examples pin the CONTRACT the strategy
# relies on — the exact SET arguments, strict-true claim semantics, TTL
# arithmetic, and that nothing is rescued. The real SET NX EX behaviour is
# exercised against the test datastore in
# try/unit/security/saml_assertion_replay_guard_try.rb.
RSpec.describe Onetime::Security::SamlAssertionReplayGuard do
  let(:dbclient) { double('dbclient') } # rubocop:disable RSpec/VerifiedDoubles
  let(:now) { Time.utc(2026, 9, 17, 12, 0, 0) }
  let(:idp) { 'https://idp.example.com/metadata' }
  let(:assertion_id) { '_8e8dc5f69a98cc4c1ff3427e5ce34606fd672f91e6' }

  def claim(**overrides)
    described_class.claim(
      idp_entity_id: idp,
      assertion_id: assertion_id,
      not_on_or_after: now + 300,
      clock_drift: 60,
      now: now,
      dbclient: dbclient,
      **overrides,
    )
  end

  describe '.claim' do
    it 'issues one SET NX EX with the digest key and the derived TTL' do
      allow(dbclient).to receive(:set).and_return(true)

      expect(claim).to be(true)
      expect(dbclient).to have_received(:set)
        .with(described_class.key_for(idp, assertion_id), '1', nx: true, ex: 360).once
    end

    it 'returns false when NX refuses the write (replay)' do
      allow(dbclient).to receive(:set).and_return(false)

      expect(claim).to be(false)
    end

    it 'treats any reply other than an explicit true as not claimed' do
      [nil, 'OK', 1, Object.new].each do |reply|
        allow(dbclient).to receive(:set).and_return(reply)

        expect(claim).to be(false)
      end
    end

    it 'propagates datastore errors so the caller fails closed' do
      allow(dbclient).to receive(:set).and_raise(Redis::CannotConnectError, 'down')

      expect { claim }.to raise_error(Redis::CannotConnectError)
    end

    it 'never touches the datastore when the assertion id is blank' do
      allow(dbclient).to receive(:set)

      [nil, '', "  \n"].each do |blank|
        expect { claim(assertion_id: blank) }.to raise_error(ArgumentError, /assertion_id/)
      end
      expect(dbclient).not_to have_received(:set)
    end

    it 'never touches the datastore when the idp entity id is blank' do
      allow(dbclient).to receive(:set)

      expect { claim(idp_entity_id: '') }.to raise_error(ArgumentError, /idp_entity_id/)
      expect(dbclient).not_to have_received(:set)
    end

    it 'never touches the datastore when NotOnOrAfter is not a Time' do
      allow(dbclient).to receive(:set)

      [nil, '2026-09-17T12:05:00Z', 1_789_646_700].each do |bad|
        expect { claim(not_on_or_after: bad) }.to raise_error(ArgumentError, /not_on_or_after/)
      end
      expect(dbclient).not_to have_received(:set)
    end
  end

  describe '.key_for' do
    it 'is prefix + sha256 hex and carries no input bytes' do
      key = described_class.key_for(idp, assertion_id)

      expect(key).to match(/\Asaml:assertion:[0-9a-f]{64}\z/)
      expect(key).not_to include('idp.example.com')
      expect(key).not_to include(assertion_id)
    end

    it 'is stable for the same pair' do
      expect(described_class.key_for(idp, assertion_id)).to eq(described_class.key_for(idp, assertion_id))
    end

    it 'scopes the assertion id by IdP' do
      expect(described_class.key_for(idp, assertion_id))
        .not_to eq(described_class.key_for('https://other.example.com/metadata', assertion_id))
    end

    it 'does not collide when bytes move across the idp/assertion boundary' do
      expect(described_class.key_for('ab', 'c')).not_to eq(described_class.key_for('a', 'bc'))
      expect(described_class.key_for('a|1:b', 'c')).not_to eq(described_class.key_for('a', 'b|1:c'))
    end

    it 'is exact-match on the entity id (no case or trailing-slash folding)' do
      expect(described_class.key_for(idp, assertion_id))
        .not_to eq(described_class.key_for("#{idp}/", assertion_id))
      expect(described_class.key_for(idp, assertion_id))
        .not_to eq(described_class.key_for(idp.upcase, assertion_id))
    end
  end

  describe '.ttl_for' do
    it 'adds the clock drift to the remaining validity' do
      expect(described_class.ttl_for(now + 300, clock_drift: 60, now: now)).to eq(360)
    end

    it 'rounds fractional remainders up (never expires before the gem would refuse)' do
      expect(described_class.ttl_for(now + 10.2, clock_drift: 0, now: now)).to eq(11)
    end

    it 'floors at MIN_TTL for an assertion that is already past NotOnOrAfter' do
      expect(described_class.ttl_for(now - 3600, clock_drift: 0, now: now)).to eq(described_class::MIN_TTL)
    end

    it 'caps at MAX_TTL for an IdP-chosen far-future NotOnOrAfter' do
      expect(described_class.ttl_for(Time.utc(9999, 1, 1), clock_drift: 60, now: now)).to eq(described_class::MAX_TTL)
    end

    it 'keeps the cap at one hour' do
      expect(described_class::MAX_TTL).to eq(3600)
    end
  end
end
