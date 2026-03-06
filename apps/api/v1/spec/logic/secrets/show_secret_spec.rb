# apps/api/v1/spec/logic/secrets/show_secret_spec.rb
#
# frozen_string_literal: true

# Tests for Bug #3: ShowSecret calls `secret.decrypted_value` (line 40)
# which crashes with NoMethodError on nil when the secret was created via
# the v2 path (Receipt.spawn_pair) that stores encrypted content in the
# `ciphertext` field, NOT the legacy `value` field.
#
# The correct method is `secret.decrypted_secret_value` which dispatches
# between v2 ciphertext and legacy value transparently.
#
# The fix (decrypted_value -> decrypted_secret_value) landed in
# show_secret.rb line 40. All tests below should now pass.

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe V1::Logic::Secrets::ShowSecret do
  let(:session) { double('Session') }
  let(:customer) { double('Onetime::Customer', anonymous?: false, custid: 'cust123', objid: 'cust_obj123', increment_field: nil ) }
  let(:owner) { double('Owner', custid: 'owner123', verified?: false, anonymous?: false, increment_field: nil ) }

  let(:secret) do
    double('Onetime::Secret',
      verification: 'false',
      key: 'secret123',
      identifier: 'secret123',
      share_domain: '')
  end

  let(:base_params) do
    {
      'key' => 'secret123',
      'passphrase' => 'pass123',
      'continue' => 'true'
    }
  end

  subject { described_class.new(session, customer, base_params) }

  before(:all) do
    OT.boot!(:test)
  end

  before do
    allow(Onetime::Secret).to receive(:load).with('secret123').and_return(secret)
    allow(secret).to receive(:load_owner).and_return(owner)
  end

  describe '#process' do
    context 'with valid secret' do
      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(false)
        allow(secret).to receive(:passphrase?).and_return(true)
        allow(secret).to receive(:can_decrypt?).and_return(true)
        allow(secret).to receive(:decrypted_secret_value).and_return('decoded_secret')
        allow(secret).to receive(:truncated?).and_return(false)
        allow(secret).to receive(:original_size).and_return(100)
        allow(secret).to receive(:viewed!)
        allow(secret).to receive(:received!)
        allow(secret).to receive(:revealed!)
        allow(secret).to receive(:previewed!)
        allow(secret).to receive(:verification).and_return('false')
        allow(secret).to receive(:state?).with(:new).and_return(true)
        allow(secret).to receive(:owner?).with(customer).and_return(false)
        allow(owner).to receive(:anonymous?).and_return(false)
      end

      it 'processes valid secret viewing' do
        subject.process

        expect(subject.show_secret).to be true
        expect(subject.secret_value).to eq('decoded_secret')
        expect(subject.correct_passphrase).to be true
      end
    end

    context 'with passphrase protected secret' do
      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(true)
        allow(secret).to receive(:passphrase?).with('pass123').and_return(false)
        allow(secret).to receive(:state?).with(:new).and_return(true)
        allow(secret).to receive(:truncated?).and_return(false)
        allow(secret).to receive(:can_decrypt?).and_return(false)
        allow(secret).to receive(:viewed!)
        allow(secret).to receive(:previewed!)
        allow(secret).to receive(:owner?).with(customer).and_return(false)
      end

      it 'handles incorrect passphrase' do
        allow(secret).to receive(:passphrase?).with('pass123').and_return(false)


        subject.process

        expect(subject.correct_passphrase).to be false
      end
    end
  end

  describe '#success_data' do
    before do
      allow(secret).to receive(:safe_dump).and_return({key: 'secret123'})
      subject.instance_variable_set(:@show_secret, true)
      subject.instance_variable_set(:@is_owner, false)
      subject.instance_variable_set(:@correct_passphrase, true)
      subject.instance_variable_set(:@display_lines, 5)
      subject.instance_variable_set(:@one_liner, true)
      subject.instance_variable_set(:@secret_value, 'secret_content')
    end

    it 'returns formatted success data' do
      result = subject.success_data

      expect(result).to include(:record, :details)
      expect(result[:record]).to include(:secret_value)
      expect(result[:details][:show_secret]).to be true
    end
  end

  # ---------------------------------------------------------------
  # Integration-style tests using real Receipt.spawn_pair objects
  # to reproduce the exact crash path from Bug #3.
  # ---------------------------------------------------------------
  describe '#process with v2 (ciphertext) secrets' do
    let(:receipt_and_secret) { Onetime::Receipt.spawn_pair('anon', 3600, 'v2 secret content') }
    let(:receipt) { receipt_and_secret[0] }
    let(:v2_secret) { receipt_and_secret[1] }
    let(:params) do
      {
        'key' => v2_secret.identifier,
        'passphrase' => '',
        'continue' => 'true'
      }
    end

    subject { described_class.new(session, customer, params) }

    before do
      allow(Onetime::Secret).to receive(:load).with(v2_secret.identifier).and_return(v2_secret)
      allow(v2_secret).to receive(:load_owner).and_return(owner)
    end

    after do
      receipt.destroy! if receipt&.exists?
      v2_secret.destroy! if v2_secret&.respond_to?(:exists?) && v2_secret.exists?
    end

    it 'does not crash when secret has ciphertext but no legacy value' do
      # Confirm the v2 precondition: ciphertext is populated, value is not
      expect(v2_secret.ciphertext.to_s).not_to be_empty
      expect(v2_secret.value.to_s).to be_empty

      expect { subject.process }.not_to raise_error
    end

    it 'populates secret_value when ciphertext is present and decryptable' do
      expect(v2_secret.can_decrypt?).to be true
      expect(v2_secret.ciphertext.to_s).not_to be_empty

      subject.process

      expect(subject.secret_value).to eq('v2 secret content')
    end
  end

  # ---------------------------------------------------------------
  # Unit-style tests with doubles, proving the method dispatch bug
  # independently of Redis / model persistence.
  # ---------------------------------------------------------------
  describe '#process method dispatch (unit)' do
    let(:v2_secret) do
      double('Onetime::Secret',
        key: 'secret_v2',
        identifier: 'secret_v2',
        share_domain: '',
        verification: 'false',
        viewable?: true,
        has_passphrase?: false,
        passphrase?: true,
        can_decrypt?: true,
        truncated?: false,
        original_size: 18,
        ciphertext: 'encrypted_blob',
        value: nil,
        value_encryption: nil)
    end

    let(:params) do
      {
        'key' => 'secret_v2',
        'passphrase' => '',
        'continue' => 'true'
      }
    end

    subject { described_class.new(session, customer, params) }

    before do
      allow(Onetime::Secret).to receive(:load).with('secret_v2').and_return(v2_secret)
      allow(v2_secret).to receive(:load_owner).and_return(owner)
      allow(v2_secret).to receive(:revealed!)
      allow(v2_secret).to receive(:previewed!)
      allow(v2_secret).to receive(:state?).with(:new).and_return(true)
      allow(v2_secret).to receive(:owner?).with(customer).and_return(false)
      allow(owner).to receive(:anonymous?).and_return(false)

      # decrypted_secret_value is the CORRECT method - returns plaintext
      allow(v2_secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

      # decrypted_value is the BUGGY call path - crashes on nil value
      allow(v2_secret).to receive(:decrypted_value).and_raise(
        NoMethodError.new("undefined method 'force_encoding' for nil")
      )
    end

    it 'calls decrypted_secret_value instead of decrypted_value' do
      expect(v2_secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

      subject.process
    end

    it 'does not call the legacy decrypted_value method' do
      expect(v2_secret).not_to receive(:decrypted_value)

      subject.process
    end

    it 'does not raise when secret has ciphertext but no legacy value' do
      expect { subject.process }.not_to raise_error
    end
  end
end
