# apps/web/billing/spec/controllers/entitlements_controller_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'
require_relative '../../plan_helpers'

RSpec.describe 'Billing::Controllers::Entitlements', :integration, :stripe_sandbox_api, :vcr do
  include Rack::Test::Methods
  include_context 'with_test_plans'

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "entitlements-test-#{SecureRandom.hex(4)}@example.com")
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

    # Mock authentication
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

  describe 'GET /billing/api/entitlements' do
    it 'returns list of all available entitlements', :vcr do
      get '/billing/api/entitlements'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('entitlements')
      expect(data).to have_key('plans')

      # Verify entitlement categories structure
      expect(data['entitlements']).to be_a(Hash)
      expect(data['entitlements']).to have_key('core')
      expect(data['entitlements']).to have_key('collaboration')
      expect(data['entitlements']).to have_key('infrastructure')

      # Verify plans summary structure
      # Note: free_v1 has no prices so it's skipped by load_all_from_config
      # identity_plus_v1 creates identity_plus_v1_monthly and identity_plus_v1_yearly
      expect(data['plans']).to be_a(Hash)
      expect(data['plans']).not_to be_empty
      first_plan = data['plans'].values.first
      expect(first_plan).to have_key('name')
      expect(first_plan).to have_key('entitlements')
      expect(first_plan).to have_key('limits')
    end

    it 'returns entitlements organized by category', :vcr do
      get '/billing/api/entitlements'

      data         = JSON.parse(last_response.body)
      entitlements = data['entitlements']

      # Verify each category contains entitlements (test config has these categories)
      expect(entitlements['core']).to be_an(Array)
      expect(entitlements['collaboration']).to be_an(Array)
      expect(entitlements['infrastructure']).to be_an(Array)
      expect(entitlements['branding']).to be_an(Array)
    end

    it 'converts infinity limits to nil in plan summaries', :vcr do
      get '/billing/api/entitlements'

      data  = JSON.parse(last_response.body)
      plans = data['plans']

      # Find a plan with unlimited limits
      unlimited_plan = plans.values.find do |plan|
        plan['limits'].any? { |_k, v| v.nil? }
      end

      expect(unlimited_plan).not_to be_nil if plans.any?
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get '/billing/api/entitlements'

      expect(last_response.status).to eq(401)
    end

    it 'handles errors gracefully', :vcr do
      # Simulate error in entitlement definitions
      allow(Billing::Config).to receive(:entitlements_grouped_by_category).and_raise(StandardError)

      get '/billing/api/entitlements'

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to list entitlements')
    end
  end

  describe 'GET /billing/api/entitlements/:extid' do
    # Plan IDs in Redis include the interval suffix
    let(:show_test_plan_id) { 'identity_plus_v1_monthly' }

    it 'returns organization entitlements and limits', :vcr do
      # Set a plan for the organization (use identity_plus_v1_monthly from billing.test.yaml)
      organization.planid = show_test_plan_id
      organization.save

      get "/billing/api/entitlements/#{organization.extid}"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('planid')
      expect(data).to have_key('plan_name')
      expect(data).to have_key('entitlements')
      expect(data).to have_key('limits')
      expect(data).to have_key('is_legacy')

      expect(data['planid']).to eq(show_test_plan_id)
      expect(data['entitlements']).to be_an(Array)
      expect(data['limits']).to be_a(Hash)
      expect([true, false]).to include(data['is_legacy'])
    end

    it 'converts infinity limits to nil', :vcr do
      organization.planid = show_test_plan_id
      organization.save

      get "/billing/api/entitlements/#{organization.extid}"

      data   = JSON.parse(last_response.body)
      limits = data['limits']

      # Verify no limit values are Float::INFINITY
      limits.each do |_key, value|
        expect(value).not_to eq(Float::INFINITY)
      end
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: "other-cap-#{SecureRandom.hex(4)}@example.com")
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/entitlements/#{organization.extid}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns 403 when organization does not exist', :vcr do
      get '/billing/api/entitlements/nonexistent_org'

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Organization not found')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/entitlements/#{organization.extid}"

      expect(last_response.status).to eq(401)
    end

    it 'handles missing plan gracefully', :vcr do
      # Organization with no plan set
      organization.planid = nil
      organization.save

      get "/billing/api/entitlements/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['limits']).to eq({})
    end
  end

  describe 'GET /billing/api/entitlements/:extid/:entitlement' do
    # Plan IDs in Redis include the interval suffix (e.g., identity_plus_v1_monthly)
    # because load_all_from_config creates "{plan_key}_{interval}ly" format
    let(:test_plan_id) { 'identity_plus_v1_monthly' }

    before do
      organization.planid = test_plan_id
      organization.save
    end

    it 'returns allowed status for granted entitlement', :vcr do
      # identity_plus_v1_monthly has api_access entitlement
      get "/billing/api/entitlements/#{organization.extid}/api_access"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['allowed']).to be(true)
      expect(data['entitlement']).to eq('api_access')
      expect(data['current_plan']).to eq(test_plan_id)
      expect(data['upgrade_needed']).to be(false)
    end

    it 'returns denied status for missing entitlement', :vcr do
      # identity_plus_v1_monthly has all entitlements in test config
      # Test with an entitlement that doesn't exist in the plan
      get "/billing/api/entitlements/#{organization.extid}/sso"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['allowed']).to be(false)
      expect(data['entitlement']).to eq('sso')
      expect(data['current_plan']).to eq(test_plan_id)
      expect(data['upgrade_needed']).to be(true)
    end

    it 'includes upgrade information when entitlement is denied', :vcr do
      # Test with an entitlement not in identity_plus_v1
      # (sso is not in the test config's identity_plus_v1 entitlements)
      get "/billing/api/entitlements/#{organization.extid}/sso"

      data = JSON.parse(last_response.body)

      if data['upgrade_needed']
        # upgrade_to may be nil if no upgrade path exists
        expect(data).to have_key('upgrade_to')

        # upgrade_plan_name and message are only set when upgrade_to is present
        if data['upgrade_to']
          expect(data).to have_key('upgrade_plan_name')
          expect(data).to have_key('message')
          expect(data['message'].downcase).to include('upgrade')
        end
      end
    end

    it 'returns 200 when entitlement parameter is missing (falls through to SPA)', :vcr do
      # Trailing slash route doesn't match /:extid/:entitlement pattern
      # Otto wildcard route catches it and returns the SPA page (200)
      get "/billing/api/entitlements/#{organization.extid}/"

      expect(last_response.status).to eq(200)
    end

    it 'treats whitespace-only entitlement as unknown', :vcr do
      # URL-encoded space (%20) is decoded to " " which is not empty
      # The controller treats it as an unknown entitlement name (returns allowed: false)
      get "/billing/api/entitlements/#{organization.extid}/%20"

      expect(last_response.status).to eq(200)
      data = JSON.parse(last_response.body)
      expect(data['allowed']).to be(false)
    end

    it 'handles unknown entitlement names', :vcr do
      get "/billing/api/entitlements/#{organization.extid}/nonexistent_entitlement"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['allowed']).to be(false)
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: "other-check-#{SecureRandom.hex(4)}@example.com")
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/entitlements/#{organization.extid}/api_access"

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/entitlements/#{organization.extid}/api_access"

      expect(last_response.status).to eq(401)
    end

    it 'builds user-friendly upgrade message', :vcr do
      # Test with an entitlement not in identity_plus_v1 (sso)
      get "/billing/api/entitlements/#{organization.extid}/sso"

      data = JSON.parse(last_response.body)

      if data['upgrade_needed'] && data['message']
        expect(data['message']).to match(/upgrade/i)
        expect(data['message']).to include(data['upgrade_plan_name']) if data['upgrade_plan_name']
      end
    end

    it 'verifies multiple entitlements in sequence', :vcr do
      entitlements_to_test = %w[api_access manage_teams custom_domains custom_branding]

      results = entitlements_to_test.map do |ent|
        get "/billing/api/entitlements/#{organization.extid}/#{ent}"
        JSON.parse(last_response.body)
      end

      # Verify each response has required fields
      results.each do |result|
        expect(result).to have_key('allowed')
        expect(result).to have_key('entitlement')
        expect(result).to have_key('current_plan')
        expect(result).to have_key('upgrade_needed')
      end
    end
  end
end
