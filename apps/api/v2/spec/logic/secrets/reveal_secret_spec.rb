# apps/api/v2/spec/logic/secrets/reveal_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Security regression coverage for the double-reveal race.
#
# Burn-after-reading requires that a secret's plaintext reach at most ONE
# caller. Secret#revealed! performs an atomic compare-and-set claim and returns
# true only to the caller that won it; RevealSecret#process must gate the
# plaintext on that return value, so a request that LOST the race to a
# concurrent reveal never emits secret_value.
#
# Uses real Receipt/Secret objects (spawn_pair) so the atomic claim runs
# against Redis exactly as it does in production. process is exercised directly
# (raise_concerns, which handles guest-gating/entitlements/rate-limits, is out
# of scope here).
RSpec.describe V2::Logic::Secrets::RevealSecret, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    store = {}
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    allow(session).to receive(:empty?).and_return(true)
    session
  end

  # Build a RevealSecret over a real secret. process derives cust from
  # strategy_result.user and never needs org (that is a raise_concerns concern).
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

  context 'when this request wins the reveal (the normal case)' do
    it 'returns the decrypted plaintext' do
      logic = build_logic('identifier' => secret.identifier, 'continue' => 'true')
      logic.process_params
      logic.process

      expect(logic.show_secret).to be true
      expect(logic.secret_value).to eq('a secret value')
      expect(logic.success_data[:record][:secret_value]).to eq('a secret value')
    end
  end

  context 'when a concurrent request already won the reveal (this request loses)' do
    it 'does NOT emit the plaintext' do
      logic = build_logic('identifier' => secret.identifier, 'continue' => 'true')
      logic.process_params # loads this request's own :new instance

      # A concurrent request wins the atomic claim and consumes the secret
      # AFTER this request has already passed its viewability check but BEFORE
      # it reveals -- the exact race window. Hold viewable? true so process
      # takes the reveal path and it is secret.reveal! (not the viewable? guard)
      # that must withhold the plaintext by losing the atomic claim.
      allow(logic.secret).to receive(:viewable?).and_return(true)
      winner = Onetime::Secret.load(secret.identifier)
      expect(winner.revealed!).to be true

      logic.process

      expect(logic.show_secret).to be false
      expect(logic.secret_value).to be_nil
      expect(logic.success_data[:record]).not_to have_key(:secret_value)
    end
  end
end
