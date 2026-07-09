# apps/api/v1/spec/logic/secrets/show_secret_spec.rb
#
# frozen_string_literal: true

# Tests for ShowSecret logic class.
# Verifies that process uses decrypted_secret_value to reveal
# v2 secrets stored in the ciphertext field.

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
        # revealed!/received! now return true for the caller that wins the
        # atomic reveal claim; the controller gates the plaintext on that value.
        allow(secret).to receive(:received!).and_return(true)
        allow(secret).to receive(:revealed!).and_return(true)
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

  # v1 show shares the passphrase rate limiter with v2 show/reveal. Wrong
  # non-empty guesses accrue attempts; the empty-passphrase preview of a
  # protected secret must never count toward the lockout.
  describe 'passphrase rate limiting' do
    let(:secret_identifier) { "showrl_#{SecureRandom.hex(6)}" }
    let(:rl_secret) do
      double('Onetime::Secret',
        verification: 'false',
        key: secret_identifier,
        identifier: secret_identifier,
        share_domain: '',
        viewable?: true,
        has_passphrase?: true,
        truncated?: false,
        can_decrypt?: false)
    end
    let(:params) do
      { 'key' => secret_identifier, 'passphrase' => 'wrong-guess', 'continue' => 'true' }
    end

    subject { described_class.new(session, customer, params) }

    before do
      allow(Onetime::Secret).to receive(:load).with(secret_identifier).and_return(rl_secret)
      allow(rl_secret).to receive(:load_owner).and_return(owner)
      allow(rl_secret).to receive(:passphrase?).and_return(false)
      allow(rl_secret).to receive(:state?).with(:new).and_return(false)
      allow(rl_secret).to receive(:owner?).with(customer).and_return(false)
    end

    it 'records failed non-empty passphrase attempts' do
      subject.process

      attempts = Onetime::Secret.dbclient.get("passphrase:attempts:#{secret_identifier}")
      expect(attempts.to_i).to eq(1)
    end

    it 'does not count the empty-passphrase preview as an attempt' do
      preview = described_class.new(session, customer, params.merge('passphrase' => ''))
      preview.process

      expect(Onetime::Secret.dbclient.get("passphrase:attempts:#{secret_identifier}")).to be_nil
    end

    it 'raises LimitExceeded from raise_concerns once locked out' do
      Onetime::Secret.dbclient.setex("passphrase:locked:#{secret_identifier}", 60, '1')

      expect { subject.raise_concerns }.to raise_error(Onetime::LimitExceeded)
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
      # Confirm the v2 precondition: ciphertext is populated. The legacy
      # `value` field has been removed from the Secret model entirely, so
      # "no legacy value" is now structurally guaranteed (the field no longer
      # exists) rather than something to assert per-record.
      expect(v2_secret.ciphertext.to_s).not_to be_empty

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
        ciphertext: 'encrypted_blob')
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
      allow(v2_secret).to receive(:revealed!).and_return(true)
      allow(v2_secret).to receive(:previewed!)
      allow(v2_secret).to receive(:state?).with(:new).and_return(true)
      allow(v2_secret).to receive(:owner?).with(customer).and_return(false)
      allow(owner).to receive(:anonymous?).and_return(false)

      allow(v2_secret).to receive(:decrypted_secret_value).and_return('v2 secret content')
    end

    it 'calls decrypted_secret_value' do
      expect(v2_secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

      subject.process
    end

    it 'does not raise when secret has ciphertext but no legacy value' do
      expect { subject.process }.not_to raise_error
    end
  end
end
