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

  describe 'VERIFICATION_HOLDS' do
    it 'registers the Entra domain-owner hold' do
      expect(described_class::VERIFICATION_HOLDS).to include('domain_unverified')
      expect(described_class::VERIFICATION_HOLDS['domain_unverified']).to include('xms_edov')
    end
  end
end
