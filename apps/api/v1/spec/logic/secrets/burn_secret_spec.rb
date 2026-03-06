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
    # Stub load_owner (the correct method name) on the secret.
    # The production code at burn_secret.rb:39 calls load_customer,
    # which does NOT exist, so process will raise NoMethodError.
    allow(secret).to receive(:load_owner).and_return(owner)
  end

  describe '#process' do
    context 'when secret is viewable and passphrase is correct' do
      before do
        allow(secret).to receive(:burned!)
      end

      it 'calls load_owner on the secret to retrieve the owner' do
        subject.process

        # This test will FAIL because the production code calls
        # secret.load_customer instead of secret.load_owner
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
  end
end
