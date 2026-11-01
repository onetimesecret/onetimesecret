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
  # federated webhook sync (#4754 review, F3).
  describe '#federation_claim_deferred?' do
    def sso_record(verified_by:, provisioning_origin: nil, verified: true)
      cust                     = customer(verified: verified, verified_by: verified_by)
      cust.provisioning_origin = provisioning_origin
      cust
    end

    it 'is true for an SSO JIT record without mailbox proof' do
      expect(sso_record(verified_by: 'sso', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(true)
      expect(sso_record(verified_by: nil, provisioning_origin: 'sso_jit', verified: false).federation_claim_deferred?).to be(true)
    end

    it "is true for an 'sso' stamp that predates provisioning_origin" do
      expect(sso_record(verified_by: 'sso').federation_claim_deferred?).to be(true)
    end

    it 'is false once an SSO record has mailbox proof' do
      expect(sso_record(verified_by: 'cli_provision', provisioning_origin: 'sso_jit').federation_claim_deferred?).to be(false)
    end

    it 'is false for a non-SSO record whatever its provenance' do
      %w[autoverify stripe_payment legacy email].each do |provenance|
        expect(sso_record(verified_by: provenance, provisioning_origin: 'canonical_signup').federation_claim_deferred?).to be(false)
      end
      expect(sso_record(verified_by: nil, verified: false).federation_claim_deferred?).to be(false)
    end
  end

  describe 'VERIFICATION_HOLDS' do
    it 'registers the Entra domain-owner hold' do
      expect(described_class::VERIFICATION_HOLDS).to include('domain_unverified')
      expect(described_class::VERIFICATION_HOLDS['domain_unverified']).to include('xms_edov')
    end
  end
end
