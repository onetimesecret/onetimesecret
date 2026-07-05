# apps/api/v1/spec/logic/secrets/show_receipt_spec.rb
#
# frozen_string_literal: true

# Tests for ShowReceipt logic class.
# Verifies that process uses decrypted_secret_value to reveal
# v2 secrets stored in the ciphertext field, and that the receipt
# endpoint follows the V2/V3 reveal rules: only generated values,
# only on first view within the display window. Concealed
# (user-supplied) plaintext is never revealed on the receipt.

require_relative '../../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')

RSpec.describe V1::Logic::Secrets::ShowReceipt do
  let(:session) { double('Session') }
  let(:customer) do
    double('Onetime::Customer',
      anonymous?: false,
      custid: 'cust123',
      increment_field: nil)
  end

  before(:all) do
    OT.boot!(:test)
  end

  # ---------------------------------------------------------------
  # Integration-style tests using real Receipt.spawn_pair objects
  # to reproduce the exact crash path from Bug #2.
  # ---------------------------------------------------------------
  describe '#process with v2 (ciphertext) secrets' do
    let(:kind) { nil }
    let(:receipt_and_secret) { Onetime::Receipt.spawn_pair('anon', 3600, 'v2 secret content', kind: kind) }
    let(:receipt) { receipt_and_secret[0] }
    let(:secret)  { receipt_and_secret[1] }
    # ShowReceipt.process_params expects the receipt's identifier (objid),
    # which is what the controller extracts from the URL path.
    let(:params)  { { 'key' => receipt.identifier } }

    subject { described_class.new(session, customer, params) }

    after do
      receipt.destroy! if receipt&.exists?
      secret.destroy! if secret&.respond_to?(:exists?) && secret.exists?
    end

    it 'does not crash when secret has ciphertext but no legacy value' do
      # Confirm the v2 precondition: ciphertext is populated. The legacy
      # `value` field has been removed from the Secret model entirely, so
      # "no legacy value" is now structurally guaranteed (the field no longer
      # exists) rather than something to assert per-record.
      expect(secret.ciphertext.to_s).not_to be_empty

      expect { subject.process }.not_to raise_error
    end

    it 'sets can_decrypt to true for v2 secrets with ciphertext' do
      subject.process

      expect(subject.can_decrypt).to be true
    end

    context 'with a concealed (user-supplied) secret' do
      it 'does not reveal the plaintext on the receipt (aligned with V2/V3)' do
        # Preconditions: the secret is decryptable, so the old V1 behavior
        # would have revealed it here.
        expect(secret.can_decrypt?).to be true
        expect(secret.ciphertext.to_s).not_to be_empty

        subject.process

        expect(subject.secret_value).to be_nil
        expect(subject.can_decrypt).to be true
      end
    end

    context 'with a generated secret' do
      let(:kind) { 'generate' }

      it 'reveals the generated value on first view within the display window' do
        expect(receipt.state?(:new)).to be true

        subject.process

        expect(subject.secret_value).to eq('v2 secret content')
      end

      it 'does not reveal the value once the receipt has been previewed' do
        receipt.previewed!

        subject.process

        expect(subject.secret_value).to be_nil
      end

      it 'does not reveal the value outside the display window' do
        display_ttl = OT.conf.dig('site', 'secret_options', 'generated_value_display_ttl').to_i
        receipt.created = Familia.now.to_i - (display_ttl + 10)
        receipt.save

        subject.process

        expect(subject.secret_value).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------
  # Unit-style tests with doubles, proving the method dispatch bug
  # independently of Redis / model persistence.
  # ---------------------------------------------------------------
  describe '#process method dispatch (unit)' do
    let(:secret) do
      double('Onetime::Secret',
        key: 'secret_abc',
        state: 'new',
        current_expiration: 3600,
        viewable?: true,
        passphrase: '',
        can_decrypt?: true,
        truncated?: false,
        ciphertext: 'encrypted_blob')
    end

    let(:receipt) do
      double('Onetime::Receipt',
        key: 'receipt_xyz',
        shortid: 'rcpt1234',
        secret_key: 'secret_abc',
        secret_shortid: 'sec1234',
        recipients: '',
        secret_natural_duration: '1 hour',
        secret_expiration: Time.now.to_i + 3600,
        secret_ttl: 3600,
        share_domain: '',
        state: 'new',
        kind: 'generate',
        created: Time.now.to_i,
        owner?: false,
        safe_dump: { key: 'receipt_xyz', state: 'new' },
        load_secret: nil) # overridden per-test below
    end

    let(:params) { { 'key' => 'receipt_xyz' } }
    subject { described_class.new(session, customer, params) }

    before do
      allow(Onetime::Receipt).to receive(:load).with('receipt_xyz').and_return(receipt)

      # load_secret is called twice in process (lines 36 and 57)
      allow(receipt).to receive(:load_secret).and_return(secret)

      # State queries
      allow(receipt).to receive(:state?).and_return(false)
      allow(receipt).to receive(:state?).with(:new).and_return(true)
      allow(receipt).to receive(:previewed!)

      # decrypted_secret_value is the CORRECT method - returns plaintext
      allow(secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

    end

    it 'calls decrypted_secret_value' do
      expect(secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

      subject.process
    end

    it 'does not raise when secret has ciphertext but no legacy value' do
      expect { subject.process }.not_to raise_error
    end

    it 'does not decrypt a concealed secret' do
      allow(receipt).to receive(:kind).and_return('conceal')

      expect(secret).not_to receive(:decrypted_secret_value)

      subject.process
      expect(subject.secret_value).to be_nil
    end
  end
end
