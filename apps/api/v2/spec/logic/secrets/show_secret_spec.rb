# apps/api/v2/spec/logic/secrets/show_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Security regression coverage for the double-reveal race (ShowSecret variant).
#
# ShowSecret#process reveals via its private reveal_secret/verify_owner helpers,
# both of which return the value of Secret#revealed!. The gate must withhold the
# plaintext whenever that atomic claim was lost to a concurrent reveal.
#
# See reveal_secret_spec.rb for the sibling RevealSecret coverage; the gate is
# duplicated per controller by design (v1 legacy and each v2 endpoint own their
# own copy rather than sharing a base implementation).
RSpec.describe V2::Logic::Secrets::ShowSecret, type: :integration do
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

      winner = Onetime::Secret.load(secret.identifier)
      expect(winner.revealed!).to be true

      logic.process

      expect(logic.show_secret).to be false
      expect(logic.success_data[:record]).not_to have_key(:secret_value)
    end
  end
end
