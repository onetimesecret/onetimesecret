# apps/web/auth/spec/operations/create_default_workspace_claim_policy_spec.rb
#
# frozen_string_literal: true

# Tests for the claim_pending_federation: kwarg on
# Auth::Operations::CreateDefaultWorkspace.
#
# There are two independent gates on the federated-subscription claim, and
# they answer different questions:
#
#   require_verification:      "not YET" — defer to after_verify_account once
#                              the user proves they own the email. Pinned by
#                              create_default_workspace_federation_spec.rb.
#   claim_pending_federation:  "not BY ME" — this caller creates workspaces but
#                              does not deliver federated benefits, and has no
#                              deferred second chance. Pinned here.
#
# The second gate exists for the checkout-completion surfaces (#4212). They
# arrive holding a paid LOCAL subscription that they apply to the workspace
# moments after creating it, so claiming the customer's cross-region pending
# record here would destroy the only copy of it to deliver a benefit they
# already have — and would leave the org flagged federated for a subscription
# it actually owns.
#
# The default is true, which is what keeps every signup-path caller (SSO,
# invite, lazy creation, standard signup) claiming exactly as before.
#
# Run: RACK_ENV=test bundle exec rspec \
#   apps/web/auth/spec/operations/create_default_workspace_claim_policy_spec.rb

require 'spec_helper'
require 'securerandom'

RSpec.describe 'CreateDefaultWorkspace: claim_pending_federation policy' do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require 'auth/operations/create_default_workspace'
    require 'billing/models/pending_federated_subscription'
  end

  # Federation requires a configured HMAC secret; EmailHash.compute reads it
  # from ENV first (see lib/onetime/utils/email_hash.rb).
  around do |example|
    original_secret = ENV['FEDERATION_SECRET']
    ENV['FEDERATION_SECRET'] = 'test_federation_secret_32chars!'
    example.run
  ensure
    ENV['FEDERATION_SECRET'] = original_secret
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }
  let(:created_pending_records) { [] }

  after do
    created_organizations.each { |org| org.delete! if org&.exists? rescue nil }
    created_customers.each { |cust| cust.delete! if cust&.exists? rescue nil }
    created_pending_records.each { |rec| rec.destroy! rescue nil }
  end

  # Verified, because this is the checkout cohort: they got here by paying,
  # and the require_verification gate is not what is under test.
  let(:email) { "claim-policy-#{SecureRandom.hex(8)}@federation-test.example.com" }
  let(:customer) do
    cust = Onetime::Customer.create!(email: email, role: 'customer', verified: true)
    created_customers << cust
    cust
  end

  # Simulate a Stripe webhook that arrived in this region before the account did.
  let!(:pending) do
    record = Billing::PendingFederatedSubscription.new(
      Onetime::Utils::EmailHash.compute(email),
    )
    record.subscription_status     = 'active'
    record.planid                  = 'pro_monthly'
    record.subscription_period_end = (Time.now + (30 * 24 * 60 * 60)).to_i.to_s
    record.region                  = 'US'
    record.received_at             = Time.now.to_i.to_s
    record.save
    created_pending_records << record
    record
  end

  def create_workspace(**kwargs)
    result = Auth::Operations::CreateDefaultWorkspace.new(customer: customer, **kwargs).call
    org    = result && result[:organization]
    created_organizations << org if org
    org
  end

  def pending_still_exists?
    hash = Onetime::Utils::EmailHash.compute(email)
    !Billing::PendingFederatedSubscription.find_by_email_hash(hash).nil?
  end

  describe 'claim_pending_federation: false (checkout completion)' do
    it 'creates the workspace without claiming the pending subscription' do
      org = create_workspace(claim_pending_federation: false)

      expect(org).to be_a(Onetime::Organization)
      expect(org.is_default).to be true
      expect(org.planid.to_s).not_to eq('pro_monthly')
      expect(org.subscription_federated?).to be false
    end

    it 'leaves the pending record intact for the surface that can resolve it' do
      create_workspace(claim_pending_federation: false)

      expect(pending_still_exists?).to be true
    end
  end

  describe 'default (every signup-path caller)' do
    it 'still claims and consumes the pending subscription' do
      org = create_workspace

      expect(org.planid).to eq('pro_monthly')
      expect(org.subscription_federated?).to be true
      expect(pending_still_exists?).to be false
    end
  end
end
