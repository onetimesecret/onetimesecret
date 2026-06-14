# apps/api/v2/spec/logic/secrets/burn_secret.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')

# Regression coverage for the v2 burn confirmation flag.
#
# BurnSecret#process must greenlight the destructive burn on the parsed
# `@continue` boolean (true / 'true' only), NOT the raw params['continue']
# string — every non-empty string is truthy in Ruby, so reading the raw param
# would burn the secret even when the caller explicitly sent continue=false.
#
# Uses real Receipt/Secret objects (spawn_pair) so process -> success_data runs
# end-to-end without stubbing the URL/serialization helpers.
RSpec.describe V2::Logic::Secrets::BurnSecret, type: :integration do
  before(:all) do
    require 'onetime'
    Onetime.boot! :test
  end

  def mock_session
    store = {}
    session = double('Session')
    allow(session).to receive(:[]) { |k| store[k] }
    allow(session).to receive(:[]=) { |k, v| store[k] = v }
    session
  end

  # Build a BurnSecret instance over a real receipt with the api_access
  # entitlement granted (we exercise process directly, not raise_concerns).
  def build_logic(params)
    customer = double('Customer', custid: 'anon', anonymous?: true, objid: nil)
    org      = double('Organization', objid: "org_#{SecureRandom.hex(4)}")
    allow(org).to receive(:can?).and_return(true)

    strategy_result = double('StrategyResult',
      session: mock_session,
      user: customer,
      metadata: { organization: org },
      auth_method: 'basicauth')

    # process derives cust from strategy_result.user and never calls org, so no
    # accessor stubbing is needed (we exercise process directly, not raise_concerns).
    described_class.new(strategy_result, params)
  end

  let!(:pair)    { Onetime::Receipt.spawn_pair(nil, 3600, 'a secret value') }
  let(:receipt)  { pair.first }
  let(:secret)   { pair.last }

  context 'when continue is the string "false"' do
    it 'does not greenlight and leaves the secret intact' do
      logic = build_logic('identifier' => receipt.identifier, 'continue' => 'false')
      logic.process_params
      logic.process

      expect(logic.greenlighted).to be_falsey
      # The secret was not burned, so it is still loadable and viewable.
      reloaded = Onetime::Secret.load(secret.identifier)
      expect(reloaded&.viewable?).to be true
    end
  end

  context 'when continue is "true"' do
    it 'greenlights and burns the secret' do
      logic = build_logic('identifier' => receipt.identifier, 'continue' => 'true')
      logic.process_params
      logic.process

      expect(logic.greenlighted).to be true
    end
  end
end
