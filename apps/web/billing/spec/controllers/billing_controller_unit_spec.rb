# apps/web/billing/spec/controllers/billing_controller_unit_spec.rb
#
# frozen_string_literal: true

# Unit tests for BillingController - business logic, validation, authorization
# These tests use local config (billing.test.yaml) and do NOT require Stripe API access.
#
# For integration tests that use VCR + Stripe API, see billing_controller_integration_spec.rb

require_relative '../support/billing_spec_helper'
require 'rack/test'

# Load the billing application for controller testing
require_relative '../../application'

# Unit tests do NOT use type: :controller to avoid automatic VCR wrapping
# The shared contexts provide all necessary setup
RSpec.describe 'Billing::Controllers::BillingController - Unit Tests' do
  include Rack::Test::Methods
  include BillingSpecHelper
  include_context 'with_test_plans'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  before do
    mock_billing_config!
  end

  # The Rack application for testing
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/plans' do
    it 'returns list of available plans' do
      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('plans')
      expect(data['plans']).to be_an(Array)

      # Verify plan structure from test config
      unless data['plans'].empty?
        plan = data['plans'].first
        expect(plan).to have_key('id')
        expect(plan).to have_key('name')
        expect(plan).to have_key('tier')
        expect(plan).to have_key('interval')
        expect(plan).to have_key('amount')
        expect(plan).to have_key('currency')
        expect(plan).to have_key('features')
        expect(plan).to have_key('limits')
        expect(plan).to have_key('entitlements')
      end
    end

    it 'does not require authentication' do
      clear_authentication

      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
    end
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns billing overview for organization' do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('organization')
      expect(data).to have_key('subscription')
      expect(data).to have_key('plan')
      expect(data).to have_key('usage')

      # Verify organization data
      expect(data['organization']['id']).to eq(organization.extid)
      expect(data['organization']['display_name']).to eq(organization.display_name)
      expect(data['organization']['billing_email']).to eq(organization.billing_email)

      # Verify usage data
      expect(data['usage']).to have_key('members')
      expect(data['usage']).to have_key('domains')
    end

    it 'returns nil subscription when organization has no subscription' do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).to be_nil
    end

    it 'returns 403 when customer is not organization member' do
      other = create_other_customer
      authenticate_as(other)

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    context 'when owner is missing from members sorted set' do
      before do
        # Simulate the bug: owner exists in org hash (owner_id) but is
        # absent from the members sorted set. This happens in fresh regions
        # where add_members_instance failed silently during org creation
        # and no migration script pre-populated the set.
        organization.remove_members_instance(customer)
        expect(organization.member?(customer)).to be(false), 'precondition: owner should not be in members set'
        expect(organization.owner?(customer)).to be(true), 'precondition: owner? should still return true'
      end

      it 'grants access to the owner and self-heals membership' do
        get "/billing/api/org/#{organization.extid}"

        expect(last_response.status).to eq(200)

        # Verify the self-healing re-added the owner to the members set
        expect(organization.member?(customer)).to be(true)
      end
    end

    it 'returns 403 when organization does not exist' do
      get '/billing/api/org/nonexistent_org_id'

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Organization not found')
    end

    it 'requires authentication' do
      clear_authentication

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(401)
    end

    context 'federation notification' do
      it 'includes federation_notification when organization is federated and not dismissed' do
        # Set up federated organization (has subscription_federated_at but no stripe_customer_id)
        organization.subscription_federated_at = Time.now.to_i
        organization.save

        get "/billing/api/org/#{organization.extid}"

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data).to have_key('federation_notification')
        expect(data['federation_notification']['show']).to be(true)
        expect(data['federation_notification']['source_region']).to be_a(String)
      end

      it 'does not include federation_notification when organization is not federated' do
        # Organization has no subscription_federated_at set
        get "/billing/api/org/#{organization.extid}"

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data).not_to have_key('federation_notification')
      end

      it 'does not include federation_notification when dismissed' do
        # Set up federated organization with dismissed notification
        organization.subscription_federated_at = Time.now.to_i
        organization.federation_notification_dismissed_at = Time.now.to_i
        organization.save

        get "/billing/api/org/#{organization.extid}"

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data).not_to have_key('federation_notification')
      end

      it 'does not include federation_notification when organization is subscription owner' do
        # Organization owns subscription (has stripe_customer_id)
        organization.subscription_federated_at = Time.now.to_i
        organization.stripe_customer_id = 'cus_test123'
        organization.save

        get "/billing/api/org/#{organization.extid}"

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data).not_to have_key('federation_notification')
      end
    end
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    let(:product) { 'identity_plus_v1' }
    let(:interval) { 'monthly' }

    it 'returns 400 when product is missing' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing product or interval')
    end

    it 'returns 400 when interval is missing' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing product or interval')
    end

    it 'returns 400 when plan resolution fails' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        product: 'nonexistent_product',
        interval: 'monthly',
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Plan not found')
    end

    it 'returns 403 when customer is not organization owner' do
      member = create_organization_member
      authenticate_as(member)

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end

    it 'requires authentication' do
      clear_authentication

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end

    # Regression: When Stripe raises a currency conflict and assess_migration
    # also fails (e.g., NoMethodError from sub.discount on newer API), the
    # controller should return 409 with a fallback assessment, not 500.
    context 'when currency conflict and assess_migration raises' do
      before do
        # Organization needs a Stripe customer to reach the checkout code path
        organization.stripe_customer_id = 'cus_currency_test'
        organization.save

        # Stub Stripe::Checkout::Session.create to raise currency conflict
        allow(Stripe::Checkout::Session).to receive(:create).and_raise(
          Stripe::InvalidRequestError.new(
            'You cannot combine currencies on a single customer. This customer has had a subscription or payment in eur, but you are trying to pay in usd.',
            'currency'
          )
        )

        # Stub assess_migration to raise NoMethodError (the original bug)
        allow(Billing::CurrencyMigrationService).to receive(:assess_migration)
          .and_raise(NoMethodError.new("undefined method 'discount' for #<Stripe::Subscription>"))
      end

      it 'returns 409 with fallback assessment instead of 500' do
        post "/billing/api/org/#{organization.extid}/checkout", {
          product: product,
          interval: interval,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(409)

        data = JSON.parse(last_response.body)
        expect(data['error']).to be true
        expect(data['code']).to eq('currency_conflict')
        expect(data['details']['existing_currency']).to eq('eur')
        expect(data['details']['requested_currency']).to eq('usd')
        # Fallback assessment: nil plan data, safe default warnings
        expect(data['details']['current_plan']).to be_nil
        expect(data['details']['requested_plan']).to be_nil
        expect(data['details']['warnings']['has_incompatible_coupons']).to be false
      end
    end
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns empty list when organization has no Stripe customer' do
      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['invoices']).to eq([])
    end

    it 'returns 403 when customer is not organization member' do
      other = create_other_customer
      authenticate_as(other)

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication' do
      clear_authentication

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(401)
    end
  end
end
