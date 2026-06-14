# apps/api/v2/spec/logic/secrets/burn_secret_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

# Regression coverage for the v2 burn endpoint mirroring the v1 spec: the
# destructive burn must be gated on the parsed `continue` boolean, not the raw
# param. Every non-empty string is truthy in Ruby, so reading params['continue']
# directly burned the secret even when the caller explicitly sent
# continue=false (the common form/query shape).
#
# V2::Logic::Base#initialize wires session/customer/org/domain context from a
# StrategyResult, none of which is relevant to the greenlight decision. We
# exercise #process in isolation by populating the inputs it reads and stubbing
# success_data (whose URL/serialization chain is out of scope here).
RSpec.describe V2::Logic::Secrets::BurnSecret do
  before(:all) { OT.boot!(:test) }

  let(:customer) do
    double('Onetime::Customer', anonymous?: false, custid: 'cust123', objid: 'cust123', increment_field: nil)
  end

  let(:secret) do
    double('Onetime::Secret',
      identifier: 'secret123',
      shortid: 'secret12',
      viewable?: true,
      has_passphrase?: false,
      passphrase?: true,
      load_owner: nil)
  end

  let(:receipt) { double('Onetime::Receipt', identifier: 'receipt123', load_secret: secret) }

  def build_subject(continue:)
    logic = described_class.allocate
    logic.instance_variable_set(:@receipt, receipt)
    logic.instance_variable_set(:@passphrase, 'pass123')
    logic.instance_variable_set(:@continue, [true, 'true'].include?(continue))
    logic.instance_variable_set(:@params, { 'continue' => continue })
    logic.instance_variable_set(:@cust, customer)
    allow(logic).to receive(:success_data).and_return({})
    logic
  end

  describe '#process' do
    before { allow(secret).to receive(:burned!) }

    context 'when continue is the string "false"' do
      subject { build_subject(continue: 'false') }

      it 'does not burn the secret' do
        subject.process

        expect(secret).not_to have_received(:burned!)
      end

      it 'does not greenlight the burn' do
        subject.process

        expect(subject.greenlighted).to be_falsey
      end
    end

    context 'when continue is the string "true"' do
      subject { build_subject(continue: 'true') }

      before do
        allow(Onetime::Customer).to receive(:secrets_burned).and_return(double('Counter', increment: 1))
      end

      it 'burns the secret' do
        subject.process

        expect(secret).to have_received(:burned!)
      end

      it 'greenlights the burn' do
        subject.process

        expect(subject.greenlighted).to be_truthy
      end
    end
  end
end
