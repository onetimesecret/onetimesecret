# spec/unit/onetime/application/authorization_policies_mailbox_spec.rb
# frozen_string_literal: true

require 'spec_helper'

# #4735 (RISK-2026-10-10-02): has_system_role? gates on MAILBOX proof, not on
# the generic verified? flag. An SSO JIT account is verified on the IdP's
# say-so (verified_by: 'sso'); separately granting it a system role must not
# make the role effective until an operator confirms the address.
RSpec.describe Onetime::Application::AuthorizationPolicies do
  let(:harness_class) do
    Class.new do
      include Onetime::Application::AuthorizationPolicies
      attr_reader :cust

      def initialize(cust)
        @cust = cust
      end
    end
  end

  def customer(role:, verified_by:, verified: true)
    cust = Onetime::Customer.new(email: "policy-#{SecureRandom.hex(4)}@example.com")
    cust.role        = role
    cust.verified    = verified
    cust.verified_by = verified_by
    cust
  end

  def policy_for(cust) = harness_class.new(cust)

  describe '#has_system_role?' do
    it 'grants the role to a colonel verified by email' do
      expect(policy_for(customer(role: 'colonel', verified_by: 'email')).has_system_role?(:colonel)).to be(true)
    end

    %w[invite_token cli_provision colonel_admin].each do |provenance|
      it "grants the role to a colonel verified by #{provenance}" do
        expect(policy_for(customer(role: 'colonel', verified_by: provenance)).has_system_role?(:colonel)).to be(true)
      end
    end

    %w[sso stripe_payment autoverify legacy].each do |provenance|
      it "refuses the role to a colonel verified by #{provenance} (no mailbox proof)" do
        cust = customer(role: 'colonel', verified_by: provenance)
        expect(cust.verified?).to be(true)
        expect(policy_for(cust).has_system_role?(:colonel)).to be(false)
      end
    end

    it 'refuses the role to a verified colonel with no provenance recorded' do
      expect(policy_for(customer(role: 'colonel', verified_by: nil)).has_system_role?(:colonel)).to be(false)
    end

    it 'refuses the role to an unverified colonel whatever the provenance says' do
      expect(policy_for(customer(role: 'colonel', verified_by: 'email', verified: false)).has_system_role?(:colonel)).to be(false)
    end

    it 'applies to admin and staff too' do
      sso_admin = customer(role: 'admin', verified_by: 'sso')
      expect(policy_for(sso_admin).has_system_role?(:admin)).to be(false)
      expect(policy_for(sso_admin).has_system_role?(:staff)).to be(false)

      email_admin = customer(role: 'admin', verified_by: 'email')
      expect(policy_for(email_admin).has_system_role?(:admin)).to be(true)
      expect(policy_for(email_admin).has_system_role?(:staff)).to be(true)
    end
  end
end
