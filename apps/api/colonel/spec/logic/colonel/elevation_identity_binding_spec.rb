# apps/api/colonel/spec/logic/colonel/elevation_identity_binding_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# The identity binding on the step-up window (#4327) — the regression set for
# the security review's B-2 finding.
#
# The rejected first draft stored a bare epoch in `sess['elevated_until']` with
# nothing recording WHO elevated. That defends the wrong boundary. The codec's
# sid/field binding already stops a Redis-writing attacker replaying one
# session's value under another sid; what leaks is an IDENTITY CHANGE WITHIN THE
# SAME SID, and this codebase has two:
#
#   - simple mode: Core::Controllers::Authentication#perform_authentication
#     assigns the new identity into the session and neither clears nor renews it
#     (compare session_helpers.rb, the other authenticate path, which does both);
#   - full mode: Rodauth's :renew after a password change carries the session
#     hash to a new sid where it is re-externalized.
#
# So the stored value is {extid, exp} and every read compares the extid against
# the CURRENT customer. Both login paths ALSO delete the field outright (see
# spec/unit/onetime/session/elevation_dropped_on_login_spec.rb); this file pins
# the read-side half, which is what holds if a third identity-change path is
# ever added.
#
# GetElevationStatus stands in for "any colonel logic class": the window
# arithmetic lives in the shared Elevation mixin included into
# ColonelAPI::Logic::Base, so every one of them answers identically.
RSpec.describe ColonelAPI::Logic::Colonel::Elevation do
  def colonel_named(extid)
    instance_double(Onetime::Customer,
      objid: "cust_#{extid}", extid: extid, email: "#{extid}@example.com",
      role: 'colonel', verified?: true, anonymous?: false, has_passphrase?: true)
  end

  let(:alice) { colonel_named('ur_alice') }
  let(:bob) { colonel_named('ur_bob') }

  # Any colonel logic class carries the mixin; this is the cheapest host.
  def logic_for(user, session)
    ColonelAPI::Logic::Colonel::GetElevationStatus.new(
      double('StrategyResult', session: session, user: user,
        auth_method: 'sessionauth', metadata: {}),
      {},
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    stub_colonel_elevation(enabled: true, window: 600)
  end

  describe 'a live window' do
    let(:session) { elevated_session('ur_alice') }

    it 'is honoured for the identity that minted it' do
      expect(logic_for(alice, session).elevated?).to be true
    end

    # The finding, in one example: sign in as B on a browser that held A's
    # elevated session and the window must not transfer.
    it 'is IGNORED for a different identity in the same session' do
      expect(logic_for(bob, session).elevated?).to be false
    end

    it 'reports no time remaining to the other identity' do
      expect(logic_for(bob, session).elevation_seconds_remaining).to eq(0)
    end
  end

  describe 'values that are not a valid record' do
    it 'ignores a bare epoch (the shape the first draft would have written)' do
      session = { 'elevated_until' => Familia.now.to_i + 600 }
      expect(logic_for(alice, session).elevated?).to be false
    end

    it 'ignores an unparseable string' do
      session = { 'elevated_until' => '{not json at all' }
      expect(logic_for(alice, session).elevated?).to be false
    end

    it 'ignores a record with a blank extid' do
      session = { 'elevated_until' => { 'extid' => '', 'exp' => Familia.now.to_i + 600 } }
      expect(logic_for(alice, session).elevated?).to be false
    end

    it 'ignores an absent field' do
      expect(logic_for(alice, {}).elevated?).to be false
    end

    it 'ignores an expired record even for its own identity' do
      expect(logic_for(alice, elevated_session('ur_alice', expires_in: -1)).elevated?).to be false
    end

    # The sidecar codec round-trips JSON objects natively, but a plaintext or
    # pre-decode read can hand back the serialized form; both must work.
    it 'accepts the JSON-string form of its own record' do
      session = { 'elevated_until' => Familia::JsonSerializer.dump(
        { 'extid' => 'ur_alice', 'exp' => Familia.now.to_i + 600 },
      ) }
      expect(logic_for(alice, session).elevated?).to be true
    end
  end

  describe 'granting and dropping' do
    it 'writes the ACTING identity, not whatever was there before' do
      session = elevated_session('ur_bob')
      logic_for(alice, session).grant_elevation!

      expect(session['elevated_until']['extid']).to eq('ur_alice')
    end

    it 'writes an exp one window ahead' do
      session = {}
      logic_for(alice, session).grant_elevation!

      expect(session['elevated_until']['exp']).to be_within(5).of(Familia.now.to_i + 600)
    end

    it 'drops the field entirely rather than parking a falsy value' do
      session = elevated_session('ur_alice')
      logic_for(alice, session).drop_elevation!

      expect(session).not_to have_key('elevated_until')
    end
  end

  describe 'the field is a registered session sidecar field' do
    # Absence must be the safe state, which is the sidecar admission rule. It is
    # externalized so the capability carries its own short TTL rather than
    # riding the 24h session blob.
    it 'is registered with the policy the design requires' do
      policy = Onetime::SessionSidecar::FIELDS[described_class::SESSION_KEY]

      expect(policy).to include(
        encrypted: true, merge_on_read: true, externalize: true, absent_when_falsy: true,
      )
      expect(policy[:ttl]).to be > described_class::DEFAULT_WINDOW
    end
  end
end
