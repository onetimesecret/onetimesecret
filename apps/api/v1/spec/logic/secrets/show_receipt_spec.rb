# apps/api/v1/spec/logic/secrets/show_receipt_spec.rb
#
# frozen_string_literal: true

# Tests for Bug #2: ShowReceipt calls `secret.decrypted_value` (line 96)
# which crashes with NoMethodError on nil when the secret was created via
# the v2 path (Receipt.spawn_pair) that stores encrypted content in the
# `ciphertext` field, NOT the legacy `value` field.
#
# The correct method is `secret.decrypted_secret_value` which dispatches
# between v2 ciphertext and legacy value transparently.
#
# The fix (decrypted_value → decrypted_secret_value) landed in
# show_receipt.rb line 96. All tests below should now pass.

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
    let(:receipt_and_secret) { Onetime::Receipt.spawn_pair('anon', 3600, 'v2 secret content') }
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
      # Confirm the v2 precondition: ciphertext is populated, value is not
      expect(secret.ciphertext.to_s).not_to be_empty
      expect(secret.value.to_s).to be_empty

      # This is the crash path: ShowReceipt#process calls
      # secret.decrypted_value which hits nil.dup.force_encoding('utf-8')
      expect { subject.process }.not_to raise_error
    end

    it 'populates secret_value when ciphertext is present and decryptable' do
      # Preconditions
      expect(secret.can_decrypt?).to be true
      expect(secret.ciphertext.to_s).not_to be_empty

      subject.process

      expect(subject.secret_value).to eq('v2 secret content')
    end

    it 'sets can_decrypt to true for v2 secrets with ciphertext' do
      subject.process

      expect(subject.can_decrypt).to be true
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
        # v2 path: ciphertext exists, value is nil
        ciphertext: 'encrypted_blob',
        value: nil,
        value_encryption: nil)
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

      # decrypted_value is the BUGGY call path - crashes on nil value
      allow(secret).to receive(:decrypted_value).and_raise(
        NoMethodError.new("undefined method 'force_encoding' for nil")
      )
    end

    it 'calls decrypted_secret_value instead of decrypted_value' do
      # The fix should call decrypted_secret_value. The current code calls
      # decrypted_value which will raise NoMethodError from our stub.
      expect(secret).to receive(:decrypted_secret_value).and_return('v2 secret content')

      subject.process
    end

    it 'does not call the legacy decrypted_value method' do
      expect(secret).not_to receive(:decrypted_value)

      subject.process
    end

    it 'does not raise when secret has ciphertext but no legacy value' do
      # Post-fix verification: process completes without error because
      # it now calls decrypted_secret_value (which handles v2 ciphertext)
      # instead of the legacy decrypted_value (which crashes on nil).
      expect { subject.process }.not_to raise_error
    end
  end
end
