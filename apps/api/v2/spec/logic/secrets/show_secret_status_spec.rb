# apps/api/v2/spec/logic/secrets/show_secret_status_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'onetime/security/request_context'

# Safe-method coverage for the status endpoint (#3633).
#
# GET /secret/:identifier/status must be a pure read: it reports the secret's
# state without advancing it. The old behavior flipped :new -> :previewed as a
# side effect of the read; these specs pin the replacement -- lifecycle stays
# put, and the fetch lands on the receipt's access timeline instead.
RSpec.describe V2::Logic::Secrets::ShowSecretStatus, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    session = double('Session')
    allow(session).to receive(:[]).and_return(nil)
    allow(session).to receive(:[]=)
    allow(session).to receive(:empty?).and_return(true)
    session
  end

  # ip:/user_agent: model the request context the auth strategy resolves into
  # StrategyResult metadata (already edge-masked by Otto in production). Left
  # nil by default so pre-existing examples exercise the no-network-context
  # path unchanged.
  def build_logic(params, ip: nil, user_agent: nil)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    metadata = { organization: org }
    metadata[:ip] = ip if ip
    metadata[:user_agent] = user_agent if user_agent

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: metadata,
      auth_method: 'basicauth')

    described_class.new(strategy_result, params)
  end

  let!(:pair)   { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt) { pair.first }
  let(:secret)  { pair.last }

  context 'with a new secret' do
    it 'reports the state without advancing it (GET is a safe method)' do
      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params
      result = logic.process

      expect(result[:record][:state]).to eq('new')

      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded.state).to eq('new')
      expect(reloaded.viewable?).to be true
    end

    it 'records the fetch on the receipt access timeline' do
      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params

      expect { logic.process }.to change {
        Onetime::Receipt.load(receipt.identifier).access_count
      }.from(0).to(1)

      timeline = Onetime::Receipt.load(receipt.identifier)
      expect(timeline.access_events.last).to start_with('status_get:')
    end

    it 'keeps reporting the same state across repeated checks' do
      3.times do
        logic = build_logic({ 'identifier' => secret.identifier })
        logic.process_params
        expect(logic.process[:record][:state]).to eq('new')
      end

      expect(Onetime::Receipt.load(receipt.identifier).access_count).to eq(3)
    end
  end

  context 'when the creator checks their own secret' do
    let(:owner) do
      Onetime::Customer.create!(email: "status-owner-#{SecureRandom.hex(6)}@example.com")
    end
    let!(:pair) { Onetime::Receipt.spawn_pair(owner.objid, 3600, 'a secret value') }

    it 'records the distinct creator_status_get kind' do
      customer = double('Customer', custid: owner.custid, objid: owner.objid, anonymous?: false)
      org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
      allow(org).to receive(:can?).and_return(true)
      strategy_result = double('StrategyResult',
        session: mock_session, user: customer,
        metadata: { organization: org }, auth_method: 'basicauth')

      logic = described_class.new(strategy_result, { 'identifier' => secret.identifier })
      logic.process_params
      logic.process

      timeline = Onetime::Receipt.load(receipt.identifier)
      expect(timeline.access_events.last).to start_with('creator_status_get:')
    end

    it 'does not misattribute an anonymous fetch of a guest secret to the creator' do
      guest_pair = Onetime::Receipt.spawn_pair(nil, 3600, 'guest secret')

      logic = build_logic({ 'identifier' => guest_pair.last.identifier })
      logic.process_params
      logic.process

      timeline = Onetime::Receipt.load(guest_pair.first.identifier)
      expect(timeline.access_events.last).to start_with('status_get:')
    end
  end

  context 'with an unknown identifier' do
    it 'returns state unknown and records nothing' do
      logic = build_logic({ 'identifier' => 'doesnotexist' })
      logic.process_params
      result = logic.process

      expect(result[:record][:state]).to eq('unknown')
    end
  end

  context 'when the receipt is already gone' do
    it 'still answers the status without raising' do
      receipt.destroy!

      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params
      result = logic.process

      expect(result[:record][:state]).to eq('new')
    end
  end

  context 'when telemetry recording fails' do
    it 'never breaks the read path' do
      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params

      allow(logic.secret).to receive(:load_receipt).and_raise(Familia::Problem, 'boom')

      result = logic.process
      expect(result[:record][:state]).to eq('new')
    end
  end

  # End-to-end network context capture (#3640, ADR-022): logic layer reads the
  # request IP/UA from StrategyResult metadata, reduces them to the privacy-safe
  # representation, and threads them through the receipt to the org trail.
  context 'network context capture' do
    let(:trail_org) do
      Onetime::Organization.new(
        display_name: 'Status Trail Org',
        contact_email: "status-trail-#{SecureRandom.hex(6)}@example.com",
      ).tap(&:save)
    end

    let!(:pair) { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }

    before do
      receipt.org_id = trail_org.objid
      receipt.save_fields(:org_id)
    end

    it 'records the masked partial IP, partial UA, and keyed hash on the status fetch' do
      logic = build_logic(
        { 'identifier' => secret.identifier },
        ip: '203.0.113.42',
        user_agent: 'Mozilla/5.0 (X11; Linux x86_64) Chrome/119.0.0.0 Safari/537.36',
      )
      logic.process_params
      logic.process

      event = Onetime::Organization.load(trail_org.objid).audit_events_page.first
      expect(event['kind']).to eq('status_get')
      expect(event['net_ip_partial']).to eq('203.0.113.0')
      expect(event['net_ip_hash']).to match(/\A[0-9a-f]{64}\z/)
      expect(event['net_ua_partial']).to include('Chrome')
      expect(event['net_ua_partial']).not_to include('119.0.0.0')
    end

    # THE NO-REGRESSION GUARD at the endpoint boundary: a raw dotted-quad IP or
    # the full UA the caller sent must never survive into the recorded event.
    it 'never persists the raw IP or full UA sent by the caller' do
      raw_ip  = '203.0.113.42'
      full_ua = 'Mozilla/5.0 (X11; Linux x86_64) Chrome/119.0.0.0 Safari/537.36'

      logic = build_logic({ 'identifier' => secret.identifier }, ip: raw_ip, user_agent: full_ua)
      logic.process_params
      logic.process

      trail = Onetime::Organization.load(trail_org.objid)
      raw   = trail.audit_events.membersraw.join
      expect(raw).not_to include(raw_ip)
      expect(raw).not_to include(full_ua)
      expect(raw).not_to include('119.0.0.0')
    end

    it 'records the event with shortids only when no request context is present' do
      logic = build_logic({ 'identifier' => secret.identifier })
      logic.process_params
      logic.process

      event = Onetime::Organization.load(trail_org.objid).audit_events_page.first
      expect(event['kind']).to eq('status_get')
      expect(event.keys).not_to include('net_ip_partial', 'net_ua_partial', 'net_ip_hash')
    end
  end
end
