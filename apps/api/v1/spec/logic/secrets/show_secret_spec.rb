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
  let(:owner) { double('Owner', custid: 'owner123', verified?: false, mailbox_verified?: false, anonymous?: false, increment_field: nil ) }

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

      # v1 reveals thread actor attribution into the lifecycle event the same
      # way v2 does (#3639); without it every v1 reveal fell to the trail's
      # fail-safe actor even when the caller was authenticated (ADR-023).
      it 'threads actor attribution into revealed! (authenticated non-owner)' do
        subject.process

        expect(secret).to have_received(:revealed!).with(
          actor_context: { 'actor' => 'authenticated_other', 'actor_id' => 'cust_obj123' },
        )
      end

      it 'threads actor=anonymous for an anonymous caller (never creator)' do
        allow(customer).to receive(:anonymous?).and_return(true)

        subject.process

        expect(secret).to have_received(:revealed!).with(
          actor_context: { 'actor' => 'anonymous' },
        )
      end
    end

    # The verification branch (#4735, #4754 review round 3). v1 is doubles
    # only, so the shared stamp is observed at its seam: the operation must be
    # built with the owner, verified: true, the 'email' provenance, the claim
    # run only for a link sent to the owner's current address and held to
    # that address, and called. Its own behaviour (the claim, the full-mode
    # skip) is covered in
    # apps/web/auth/spec/operations/set_customer_verification_spec.rb and the
    # v2 integration specs, both address checks in
    # apps/web/auth/spec/operations/ensure_default_workspace_federation_spec.rb.
    context 'when the secret is a verification secret' do
      let(:verification_op) { instance_double(Auth::Operations::SetCustomerVerification, call: :success) }

      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(false)
        allow(secret).to receive(:can_decrypt?).and_return(true)
        allow(secret).to receive(:decrypted_secret_value).and_return('decoded_secret')
        allow(secret).to receive(:truncated?).and_return(false)
        allow(secret).to receive(:original_size).and_return(100)
        allow(secret).to receive(:revealed!).and_return(true)
        allow(secret).to receive(:verification).and_return('true')
        allow(secret).to receive(:owner?).with(customer).and_return(false)
        # The emailed link is opened by an anonymous caller; the v1 controllers
        # pass no session (sess is nil in the logic).
        allow(customer).to receive(:anonymous?).and_return(true)
        allow(owner).to receive(:mailbox_proof_secret?).with(secret).and_return(true)
        allow(owner).to receive(:extid).and_return('ur_owner123')
        allow(owner).to receive(:email).and_return('owner@example.com')
        # The welcome link was sent to the owner's current address.
        allow(secret).to receive(:delivered_to?).with('owner@example.com').and_return(true)
        allow(secret).to receive(:delivery_digest).and_return('digest-of-current-address')
        allow(Auth::Operations::SetCustomerVerification).to receive(:new).and_return(verification_op)
      end

      subject { described_class.new(nil, customer, base_params) }

      it 'stamps the owner through the verification operation, then reveals' do
        subject.process

        expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
          customer: owner, verified: true, verified_by: 'email',
          claim_pending_federation: true, claim_own_address_only: true
        ).ordered
        expect(verification_op).to have_received(:call).ordered
        expect(secret).to have_received(:revealed!).ordered
        expect(subject.show_secret).to be true
        expect(subject.secret_value).to eq('decoded_secret')
      end

      # A link sent to another address (before an operator changed the
      # owner's) proves only that mailbox: the stamp is written as before,
      # without the claim.
      it 'builds the operation without the claim for a link sent to another address' do
        allow(secret).to receive(:delivered_to?).with('owner@example.com').and_return(false)
        allow(Auth::Operations::SetCustomerVerification).to receive(:auth_logger)
          .and_return(double('AuthLogger', info: nil))

        subject.process

        expect(Auth::Operations::SetCustomerVerification).to have_received(:new).with(
          customer: owner, verified: true, verified_by: 'email',
          claim_pending_federation: false, claim_own_address_only: true
        )
        expect(verification_op).to have_received(:call)
        expect(secret).to have_received(:revealed!)
      end

      it 'does not build the operation for a secret that is not mailbox proof' do
        allow(owner).to receive(:mailbox_proof_secret?).with(secret).and_return(false)

        subject.process

        expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
        expect(secret).to have_received(:revealed!)
        expect(subject.show_secret).to be true
      end

      # A link minted in simple mode and followed after a switch to full auth
      # mode: Rodauth owns verification there, so the shared stamp builds no
      # operation (no SQL is reached) and the reveal still proceeds. The owner
      # double answers no writer, so a stamp written anyway would raise.
      it 'reveals without building the operation in full auth mode' do
        allow(Onetime.auth_config).to receive(:mode).and_return('full')
        auth_logger = double('AuthLogger', info: nil)
        allow(Auth::Operations::SetCustomerVerification).to receive(:auth_logger).and_return(auth_logger)

        subject.process

        expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
        expect(verification_op).not_to have_received(:call)
        expect(secret).to have_received(:revealed!)
        expect(subject.show_secret).to be true
        expect(subject.secret_value).to eq('decoded_secret')
        expect(auth_logger).to have_received(:info).with(
          /redeemed in full auth mode; Rodauth owns account verification there/,
          { customer: 'ur_owner123' },
        )
      end

      it 'raises when the caller is logged in as a different user' do
        allow(customer).to receive(:anonymous?).and_return(false)

        expect { subject.process }.to raise_error(Onetime::FormError, /already logged in/)
        expect(Auth::Operations::SetCustomerVerification).not_to have_received(:new)
        expect(secret).not_to have_received(:revealed!)
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

    # Passphrase oracle regression: the guess is verified ONLY on a committed
    # reveal (continue=true). A metadata-only request must learn nothing about
    # the guess -- no correct_passphrase in the payload and no rate-limit state
    # touched, because nothing was checked.
    context 'when continue is false on a passphrase-protected secret' do
      subject { described_class.new(session, customer, base_params.merge('continue' => 'false')) }

      before do
        allow(secret).to receive(:viewable?).and_return(true)
        allow(secret).to receive(:has_passphrase?).and_return(true)
        allow(secret).to receive(:passphrase?).and_return(false)
        allow(secret).to receive(:owner?).with(customer).and_return(false)
        allow(secret).to receive(:safe_dump).and_return({ key: 'secret123' })
      end

      it 'never checks the passphrase' do
        expect(secret).not_to receive(:passphrase?)

        subject.process
      end

      it 'exposes no correct_passphrase in the response details' do
        subject.process

        expect(subject.show_secret).to be false
        expect(subject.success_data[:details]).not_to have_key(:correct_passphrase)
        expect(subject.success_data[:record]).not_to have_key(:secret_value)
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

    # A continue=false guess is not an attempt: the passphrase was never
    # checked, so the limiter must neither accrue nor clear anything.
    it 'does not count a continue=false guess as an attempt' do
      probe = described_class.new(session, customer, params.merge('continue' => 'false'))
      expect(rl_secret).not_to receive(:passphrase?)

      probe.process

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
      subject.instance_variable_set(:@display_lines, 5)
      subject.instance_variable_set(:@one_liner, true)
      subject.instance_variable_set(:@secret_value, 'secret_content')
    end

    it 'returns formatted success data' do
      result = subject.success_data

      expect(result).to include(:record, :details)
      expect(result[:record]).to include(:secret_value)
      expect(result[:details][:show_secret]).to be true
      # The passphrase verdict is never serialized to the client -- it is an
      # oracle for anyone probing with continue=false.
      expect(result[:details]).not_to have_key(:correct_passphrase)
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
