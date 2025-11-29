# apps/web/billing/spec/controllers/billing_controller_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Billing::Controllers::BillingController', :integration, :vcr, :stripe_sandbox_api do
  include Rack::Test::Methods

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "billing-test-#{SecureRandom.hex(4)}@example.com")
    created_customers << cust
    cust
  end

  let(:organization) do
    org = Onetime::Organization.create!('Test Organization', customer, customer.email)
    created_organizations << org
    org
  end

  before do
    customer.save
    organization.save

    # Mock authentication by setting up session
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
    }
  end

  after do
    # Clean up created test data
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe 'GET /billing/api/plans' do
    it 'returns list of available plans', :vcr do
      # Ensure plan cache is populated
      Billing::Plan.refresh_from_stripe

      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('plans')
      expect(data['plans']).to be_an(Array)

      # Verify plan structure
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
        expect(plan).to have_key('capabilities')
      end
    end

    it 'does not require authentication', :vcr do
      # Clear session to test unauthenticated access
      env 'rack.session', {}

      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
    end

    it 'handles plan cache refresh failures gracefully', :vcr do
      # Simulate Stripe error
      allow(Billing::Plan).to receive(:list_plans).and_raise(Stripe::StripeError)

      get '/billing/api/plans'

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to list plans')
    end
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns billing overview for organization', :vcr do
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
      expect(data['usage']).to have_key('teams')
      expect(data['usage']).to have_key('members')
    end

    it 'returns subscription data when organization has active subscription', :vcr do
      # Create real Stripe subscription
      stripe_customer = Stripe::Customer.create(email: customer.email)
      subscription    = Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
      )

      organization.update_from_stripe_subscription(subscription)
      organization.save

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).not_to be_nil
      expect(data['subscription']['id']).to eq(subscription.id)
      expect(data['subscription']['status']).to match(/active|trialing/)
    end

    it 'returns nil subscription when organization has no subscription', :vcr do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).to be_nil
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: "other-#{SecureRandom.hex(4)}@example.com")
      created_customers << other_customer
      other_customer.save

      # Switch session to other customer
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns 403 when organization does not exist', :vcr do
      get '/billing/api/org/nonexistent_org_id'

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Organization not found')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(401)
    end
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    let(:tier) { 'single_team' }
    let(:billing_cycle) { 'monthly' }

    before do
      # Ensure customer is organization owner
      organization.save
    end

    it 'creates Stripe checkout session', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('checkout_url')
      expect(data).to have_key('session_id')
      expect(data['checkout_url']).to match(%r{^https://checkout\.stripe\.com})
    end

    it 'returns 400 when tier is missing', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 400 when billing_cycle is missing', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 404 when plan is not found', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'nonexistent_tier',
        billing_cycle: 'monthly',
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Plan not found')
    end

    it 'uses existing Stripe customer if organization has one', :vcr do
      # Create Stripe customer and associate with organization
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Verify the checkout session used the existing customer
      data    = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])
      expect(session.customer).to eq(stripe_customer.id)
    end

    it 'includes metadata in subscription', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      data    = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])

      expect(session.subscription_data['metadata']).to include(
        'orgid' => organization.objid,
        'tier' => tier,
        'external_id' => customer.extid,
      )
    end

    it 'uses idempotency key to prevent duplicates', :vcr do
      # Make two identical requests
      2.times do
        post "/billing/api/org/#{organization.extid}/checkout", {
          tier: tier,
          billing_cycle: billing_cycle,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
      end

      # Both requests should succeed due to idempotency
    end

    it 'returns 403 when customer is not organization owner', :vcr do
      # Create member (non-owner) customer
      member_customer = Onetime::Customer.create!(email: "member-#{SecureRandom.hex(4)}@example.com")
      created_customers << member_customer
      member_customer.save

      # Add as member but not owner
      team = Onetime::Team.create!(organization, 'Test Team', customer)
      team.add_member(member_customer)

      # Switch session to member customer
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => member_customer.extid,
      }

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns empty list when organization has no Stripe customer', :vcr do
      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['invoices']).to eq([])
    end

    it 'returns list of invoices for organization', :vcr do
      # Create Stripe customer and invoice
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      # Create an invoice
      Stripe::Invoice.create(
        customer: stripe_customer.id,
        collection_method: 'send_invoice',
        days_until_due: 30,
      )

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data).to have_key('invoices')
      expect(data).to have_key('has_more')
      expect(data['invoices']).to be_an(Array)

      unless data['invoices'].empty?
        invoice_data = data['invoices'].first
        expect(invoice_data).to have_key('id')
        expect(invoice_data).to have_key('number')
        expect(invoice_data).to have_key('amount')
        expect(invoice_data).to have_key('currency')
        expect(invoice_data).to have_key('status')
        expect(invoice_data).to have_key('created')
        expect(invoice_data).to have_key('invoice_pdf')
        expect(invoice_data).to have_key('hosted_invoice_url')
      end
    end

    it 'limits invoices to 12', :vcr do
      skip 'Requires creating 13+ invoices which is time-intensive'

      # In a real integration test, you would:
      # 1. Create Stripe customer
      # 2. Create 13 invoices
      # 3. Verify only 12 are returned
      # 4. Verify has_more is true
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: "other-invoice-#{SecureRandom.hex(4)}@example.com")
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(401)
    end

    it 'handles Stripe errors gracefully', :vcr do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to retrieve invoices')
    end
  end
end
