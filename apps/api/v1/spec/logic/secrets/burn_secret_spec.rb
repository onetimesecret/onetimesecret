# apps/api/v1/spec/logic/secrets/burn_secret_spec.rb
#
# frozen_string_literal: true

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe V1::Logic::Secrets::BurnSecret do
  let(:session) { double('Session') }
  let(:customer) { double('Onetime::Customer', anonymous?: false, custid: 'cust123', increment_field: nil) }
  let(:owner) { double('Owner', custid: 'owner123', verified?: false, anonymous?: false, increment_field: nil) }

  let(:secret) do
    double('Onetime::Secret',
      key: 'secret123',
      state?: true,
      owner?: false,
      viewable?: true,
      has_passphrase?: false,
      passphrase?: true)
  end

  let(:receipt) do
    double('Onetime::Receipt',
      key: 'receipt123',
      secret_key: 'secret123',
      share_domain: '',
      recipients: '',
      default_expiration: '86400',
      created: Time.now.to_i.to_s,
      safe_dump: { key: 'receipt123' },
      load_secret: secret)
  end

  let(:base_params) do
    {
      'key' => 'receipt123',
      'passphrase' => 'pass123',
      'continue' => 'true'
    }
  end

  subject { described_class.new(session, customer, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Onetime::Receipt).to receive(:load).with('receipt123').and_return(receipt)
    # Stub load_owner on the secret — process calls it to resolve the owner
    # before incrementing their secrets_burned counter.
    allow(secret).to receive(:load_owner).and_return(owner)
  end

  describe '#process' do
    context 'when secret is viewable and passphrase is correct' do
      before do
        allow(secret).to receive(:burned!).and_return(true)
      end

      it 'calls load_owner on the secret to retrieve the owner' do
        subject.process

        expect(secret).to have_received(:load_owner)
      end

      it 'increments secrets_burned on the owner' do
        subject.process

        expect(owner).to have_received(:increment_field).with(:secrets_burned)
      end

      it 'marks the secret as burned' do
        subject.process

        expect(secret).to have_received(:burned!)
      end
    end

    # The double-reveal race, burn variant: Secret#burned! performs an atomic
    # compare-and-set claim and returns true only to the caller that won it. A
    # burn that loses the claim (a concurrent reveal or burn already consumed
    # the secret) must not count the burn nor report success.
    context 'when the burn loses the race to a concurrent reveal or burn' do
      before do
        allow(secret).to receive(:burned!).and_return(false)
      end

      it 'does not increment secrets_burned on the owner' do
        subject.process

        expect(secret).to have_received(:burned!)
        expect(owner).not_to have_received(:increment_field)
      end

      it 'is not greenlighted' do
        subject.process

        expect(subject.greenlighted).to be false
        # Proves it was the gate (burned! returning false), not the
        # viewable?/continue guard, that withheld the greenlight -- the guard
        # path never calls burned! at all.
        expect(secret).to have_received(:burned!)
      end
    end

    # Regression: the greenlight must honor the parsed `continue` boolean, not
    # the raw param. The string "false" is truthy in Ruby, so the previous
    # `continue_result = params['continue']` would burn a secret even when the
    # caller explicitly passed continue=false.
    context 'when continue is the string "false"' do
      subject { described_class.new(session, customer, base_params.merge('continue' => 'false')) }

      before do
        allow(secret).to receive(:burned!).and_return(true)
      end

      it 'does not burn the secret' do
        subject.process

        expect(secret).not_to have_received(:burned!)
      end

      it 'is not greenlighted' do
        subject.process

        expect(subject.greenlighted).to be_falsey
      end
    end
  end
end
