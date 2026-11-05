# spec/unit/onetime/models/customer/mailbox_verified_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# Customer#mailbox_verified? (#4735): which verified_by provenances record
# proof that the person controls the mailbox. The list is explicit and
# fail-closed; verified? stays the broader "account is open" predicate.
RSpec.describe Onetime::Customer do
  def customer(verified:, verified_by:)
    cust = described_class.new(email: "mailbox-#{SecureRandom.hex(4)}@example.com")
    cust.verified    = verified
    cust.verified_by = verified_by
    cust
  end

  describe 'MAILBOX_VERIFIED_BY' do
    it 'names exactly the provenances that prove mailbox control' do
      expect(described_class::MAILBOX_VERIFIED_BY).to contain_exactly('email', 'invite_token', 'colonel_admin', 'cli_provision')
    end

    it 'is a subset of every provenance the codebase writes' do
      require 'auth/operations/customers/doctor'
      expect(Auth::Operations::Customers::Doctor::VALID_VERIFIED_BY).to include(*described_class::MAILBOX_VERIFIED_BY)
    end
  end

  describe '#mailbox_verified?' do
    %w[email invite_token colonel_admin cli_provision].each do |provenance|
      it "is true for a verified customer stamped #{provenance}" do
        cust = customer(verified: true, verified_by: provenance)
        expect(cust.verified?).to be(true)
        expect(cust.mailbox_verified?).to be(true)
      end
    end

    %w[sso stripe_payment autoverify legacy].each do |provenance|
      it "is false for a verified customer stamped #{provenance}, although verified? is true" do
        cust = customer(verified: true, verified_by: provenance)
        expect(cust.verified?).to be(true)
        expect(cust.mailbox_verified?).to be(false)
      end
    end

    it 'is false for a verified customer with no provenance (fail closed)' do
      expect(customer(verified: true, verified_by: nil).mailbox_verified?).to be(false)
      expect(customer(verified: true, verified_by: '').mailbox_verified?).to be(false)
    end

    it 'is false for an unverified customer even with a qualifying provenance' do
      expect(customer(verified: false, verified_by: 'email').mailbox_verified?).to be(false)
    end
  end

  # The record-based deferral rule shared by the federation claim and the
  # federated webhook sync (#4754 review, F3 and F1). verify_account is off
  # under RACK_ENV=test (etc/auth.yaml), so the verify-enabled examples stub
  # the config predicate the rule reads.
  describe '#federation_claim_deferred?' do
    def record(verified_by:, provisioning_origin: nil, verified: true)
      cust                     = customer(verified: verified, verified_by: verified_by)
      cust.provisioning_origin = provisioning_origin
      cust
    end

    def verify_account(loaded)
      allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_return(loaded)
    end

    describe 'with mailbox proof' do
      %w[email invite_token colonel_admin cli_provision].each do |provenance|
        it "is false for a verified customer stamped #{provenance}, with or without a verification step" do
          [true, false].each do |loaded|
            verify_account(loaded)
            expect(record(verified_by: provenance, provisioning_origin: 'canonical_signup').federation_claim_deferred?).to be(false)
          end
        end
      end

      it 'is false once an SSO record has mailbox proof' do
        verify_account(true)
        expect(record(verified_by: 'cli_provision', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(false)
      end
    end

    describe 'an IdP-asserted address' do
      it 'is true for an SSO JIT record without mailbox proof, whatever the verification step' do
        [true, false].each do |loaded|
          verify_account(loaded)
          expect(record(verified_by: 'sso', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(true)
          expect(record(verified_by: nil, provisioning_origin: 'sso_jit', verified: false).federation_claim_deferred?).to be(true)
        end
      end

      it "is true for an 'sso' stamp that predates provisioning_origin" do
        verify_account(false)
        expect(record(verified_by: 'sso').federation_claim_deferred?).to be(true)
      end
    end

    describe 'an unverified standard signup' do
      # The doctor's repair, lazy creation and the billing self-heal create
      # the workspace with the default flag; the record must carry the
      # deferral itself (#4754 review, F1).
      it 'is true while the deployment has a verification step that will prove it' do
        verify_account(true)
        expect(record(verified_by: nil, verified: false, provisioning_origin: 'canonical_signup').federation_claim_deferred?).to be(true)
        expect(record(verified_by: nil, verified: false, provisioning_origin: 'domain_signup').federation_claim_deferred?).to be(true)
        expect(record(verified_by: nil, verified: false).federation_claim_deferred?).to be(true)
      end

      it 'is false when the deployment has no verification step (the documented residual)' do
        verify_account(false)
        expect(record(verified_by: nil, verified: false, provisioning_origin: 'canonical_signup').federation_claim_deferred?).to be(false)
        expect(record(verified_by: nil, verified: false).federation_claim_deferred?).to be(false)
      end

      it 'does not read the config when the record is already decided' do
        allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_raise('must not be read')
        expect(record(verified_by: 'email').federation_claim_deferred?).to be(false)
        expect(record(verified_by: 'sso', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(true)
      end
    end

    describe 'a verified record without mailbox proof' do
      # Deliberate: Rodauth never re-verifies a Verified row, so these
      # accounts have no self-service way to produce mailbox proof. Deferring
      # them would strand a new cross-region plan until an operator stamped
      # it, and an attacker cannot obtain any of these stamps on a deployment
      # with a verification step. Only the claim path's audit log concerns
      # them (EnsureDefaultWorkspace#unverified_immediate_claim?).
      %w[autoverify stripe_payment legacy].each do |provenance|
        it "is false for a verified non-SSO record stamped #{provenance}, even with a verification step" do
          verify_account(true)
          expect(record(verified_by: provenance, provisioning_origin: 'canonical_signup').federation_claim_deferred?).to be(false)
        end
      end

      it 'is false for a verified non-SSO record with a blank provenance' do
        verify_account(true)
        expect(record(verified_by: nil).federation_claim_deferred?).to be(false)
        expect(record(verified_by: '').federation_claim_deferred?).to be(false)
      end
    end

    describe 'when the auth config cannot be read' do
      # Fail closed: an unreadable config defers rather than hands a benefit
      # to an address nobody proved. The webhook path reads the predicate
      # under its federation lock, so the error must not propagate either.
      # Unit specs do not boot, so the Auth logger is not cached; stub the
      # record's own accessor rather than one SemanticLogger instance.
      let(:logger) { instance_double(SemanticLogger::Logger, warn: nil) }

      def unverified_record_with_logger
        cust = record(verified_by: nil, verified: false)
        allow(cust).to receive(:auth_logger).and_return(logger)
        cust
      end

      it 'defers an unverified record and logs the exception itself' do
        allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_raise(RuntimeError, 'config exploded')

        expect(unverified_record_with_logger.federation_claim_deferred?).to be(true)
        # The exception OBJECT under :exception. SemanticLogger formats that
        # key itself and replaces a class-name string with an ArgumentError
        # ("Invalid value for logger exception"), which would hide the cause.
        expect(logger).to have_received(:warn).with(
          a_string_matching(/verify_account config/),
          a_hash_including(exception: an_instance_of(RuntimeError).and(having_attributes(message: 'config exploded'))),
        )
      end

      it 'defers when Onetime.auth_config itself raises' do
        allow(Onetime).to receive(:auth_config).and_raise(RuntimeError, 'no config')

        expect(unverified_record_with_logger.federation_claim_deferred?).to be(true)
        expect(logger).to have_received(:warn)
      end

      it 'still returns false for a record with mailbox proof' do
        allow(Onetime).to receive(:auth_config).and_raise(RuntimeError, 'no config')
        expect(record(verified_by: 'email').federation_claim_deferred?).to be(false)
      end
    end

    describe 'when the process resolved simple mode by default' do
      # A bin/ots shell, or a worker or scheduler container, that did not
      # export AUTHENTICATION_MODE resolves simple mode whatever the install
      # runs (Onetime::AuthConfig#simple_by_default?) and reads
      # verify_account_loaded? as false with nothing raised, so the rescue
      # above never ran and on a full-mode install such a process read the
      # verification step as absent and claimed at once (#4754 review, F1
      # follow-up). Fail closed on the unsettled mode as on an unreadable
      # config: the process cannot tell a simple-mode install from a
      # full-mode one whose verification step will still prove the address.
      let(:logger) { instance_double(SemanticLogger::Logger, warn: nil) }

      before do
        allow(Onetime.auth_config).to receive_messages(simple_by_default?: true, verify_account_loaded?: false)
      end

      def with_logger(cust)
        allow(cust).to receive(:auth_logger).and_return(logger)
        cust
      end

      it 'defers an unverified record and warns, naming the variable to export' do
        cust = with_logger(record(verified_by: nil, verified: false, provisioning_origin: 'canonical_signup'))

        expect(cust.federation_claim_deferred?).to be(true)
        expect(logger).to have_received(:warn).with(
          a_string_matching(/AUTHENTICATION_MODE/),
          a_hash_including(customer: cust.custid),
        )
      end

      it 'does not consult the verification step at all' do
        allow(Onetime.auth_config).to receive(:verify_account_loaded?).and_raise('must not be read')

        expect(with_logger(record(verified_by: nil, verified: false)).federation_claim_deferred?).to be(true)
        # The unsettled-mode warning, not the unreadable-config one.
        expect(logger).to have_received(:warn).with(a_string_matching(/AUTHENTICATION_MODE/), anything)
      end

      it 'leaves a decided record alone' do
        expect(record(verified_by: 'email').federation_claim_deferred?).to be(false)
        expect(record(verified_by: 'autoverify').federation_claim_deferred?).to be(false)
        expect(record(verified_by: 'sso', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(true)
        expect(logger).not_to have_received(:warn)
      end

      it 'keeps the documented residual once the shell settles simple mode' do
        allow(Onetime.auth_config).to receive(:simple_by_default?).and_return(false)
        cust = with_logger(record(verified_by: nil, verified: false))

        expect(cust.federation_claim_deferred?).to be(false)
        expect(logger).not_to have_received(:warn)
      end
    end
  end

  describe 'VERIFICATION_HOLDS' do
    it 'registers the Entra domain-owner hold' do
      expect(described_class::VERIFICATION_HOLDS).to include('domain_unverified')
      expect(described_class::VERIFICATION_HOLDS['domain_unverified']).to include('xms_edov')
    end
  end
end
