# apps/api/v2/spec/logic/secrets/show_secret_status_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

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

  def build_logic(params)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org },
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
end
