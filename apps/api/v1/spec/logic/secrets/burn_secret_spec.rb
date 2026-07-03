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
        allow(secret).to receive(:burned!)
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

    # Regression: the greenlight must honor the parsed `continue` boolean, not
    # the raw param. The string "false" is truthy in Ruby, so the previous
    # `continue_result = params['continue']` would burn a secret even when the
    # caller explicitly passed continue=false.
    context 'when continue is the string "false"' do
      subject { described_class.new(session, customer, base_params.merge('continue' => 'false')) }

      before do
        allow(secret).to receive(:burned!)
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

    # v1 burn shares the passphrase rate limiter with show/reveal so the burn
    # endpoint cannot be used as a free brute-force oracle.
    context 'when the secret is passphrase-protected' do
      let(:secret_identifier) { "burnrl_#{SecureRandom.hex(6)}" }
      let(:secret) do
        double('Onetime::Secret',
          key: 'secret123',
          identifier: secret_identifier,
          state?: true,
          owner?: false,
          viewable?: true,
          has_passphrase?: true,
          passphrase?: false)
      end

      before do
        allow(secret).to receive(:burned!)
      end

      it 'records a failed attempt and raises a form error on a wrong guess' do
        expect { subject.process }.to raise_error(OT::FormError)

        attempts = Onetime::Secret.dbclient.get("passphrase:attempts:#{secret_identifier}")
        expect(attempts.to_i).to eq(1)
        expect(secret).not_to have_received(:burned!)
      end

      it 'rejects further attempts once locked out, before checking the passphrase' do
        Onetime::Secret.dbclient.setex("passphrase:locked:#{secret_identifier}", 60, '1')

        expect { subject.process }.to raise_error(Onetime::LimitExceeded)
        expect(secret).not_to have_received(:burned!)
      end

      context 'with the correct passphrase' do
        let(:secret) do
          double('Onetime::Secret',
            key: 'secret123',
            identifier: secret_identifier,
            state?: true,
            owner?: false,
            viewable?: true,
            has_passphrase?: true,
            passphrase?: true)
        end

        it 'clears rate limit state and burns' do
          Onetime::Secret.dbclient.set("passphrase:attempts:#{secret_identifier}", '3')

          subject.process

          expect(secret).to have_received(:burned!)
          expect(Onetime::Secret.dbclient.get("passphrase:attempts:#{secret_identifier}")).to be_nil
        end
      end
    end
  end
end
