# frozen_string_literal: true

require 'spec_helper'
require 'onetime/models/organization/features/with_organization_billing'
require 'onetime/models/organization'

RSpec.describe 'Organization billing features' do
  let(:customer) do
    Onetime::Customer.create!(
      email: "billing-test-#{SecureRandom.hex(4)}@example.com"
    )
  end

  let(:organization) do
    Onetime::Organization.create!(
      'Test Billing Org',
      customer,
      customer.email
    )
  end

  after do
    organization.destroy! if organization
  end

  describe 'billing fields' do
    it 'has stripe_customer_id field' do
      expect(organization).to respond_to(:stripe_customer_id)
    end

    it 'has subscription_status field' do
      expect(organization).to respond_to(:subscription_status)
    end

    it 'has planid field' do
      expect(organization).to respond_to(:planid)
    end

    it 'sets and persists billing fields' do
      organization.stripe_customer_id = 'cus_test123'
      organization.stripe_subscription_id = 'sub_test123'
      organization.subscription_status = 'active'
      organization.subscription_period_end = (Time.now + 30 * 24 * 60 * 60).to_i.to_s
      organization.planid = 'single_team_monthly_us_east'
      organization.billing_email = 'billing@example.com'

      expect(organization.save).to be true

      reloaded = Onetime::Organization.load(organization.objid)
      expect(reloaded.stripe_customer_id).to eq 'cus_test123'
    end
  end

  describe 'subscription status checks' do
    it 'recognizes active subscription' do
      organization.subscription_status = 'active'
      organization.save

      expect(organization.active_subscription?).to be true
    end

    it 'recognizes trialing as active subscription' do
      organization.subscription_status = 'trialing'
      organization.save

      expect(organization.active_subscription?).to be true
    end

    it 'recognizes past_due status' do
      organization.subscription_status = 'past_due'
      organization.save

      expect(organization.past_due?).to be true
    end

    it 'recognizes canceled status' do
      organization.subscription_status = 'canceled'
      organization.save

      expect(organization.canceled?).to be true
    end
  end

  describe '#clear_billing_fields' do
    before do
      organization.stripe_customer_id = 'cus_test123'
      organization.stripe_subscription_id = 'sub_test123'
      organization.subscription_status = 'active'
      organization.save
    end

    it 'clears billing data' do
      organization.clear_billing_fields

      expect(organization.subscription_status).to eq 'canceled'
      expect(organization.stripe_subscription_id).to be_nil
    end
  end
end
