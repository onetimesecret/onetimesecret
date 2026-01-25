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
