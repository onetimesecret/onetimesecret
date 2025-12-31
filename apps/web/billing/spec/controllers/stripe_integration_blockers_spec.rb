# apps/web/billing/spec/controllers/stripe_integration_blockers_spec.rb
#
# frozen_string_literal: true

# Test suite for Stripe Integration Blockers (Issue #2309)
# Covers API-related blockers:
# - BLOCKER 1 & 2: Plans API returns empty for monthly/yearly
# - BLOCKER 3: Receipt recent API returns 403
# - BLOCKER 7: Plans endpoint returns {"plans":[]}
# - BLOCKER 8: Entitlements endpoint returns 500

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

require_relative '../../application'
require_relative '../../plan_helpers'

RSpec.describe 'Stripe Integration Blockers', :integration, :stripe_sandbox_api, :vcr do
  include Rack::Test::Methods
  include_context 'with_test_plans'

  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "blocker-test-#{SecureRandom.hex(4)}@example.com")
    created_customers << cust
    cust
  end

  let(:organization) do
    org = Onetime::Organization.create!('Blocker Test Org', customer, customer.email)
    org.is_default = true
    org.save
    created_organizations << org
    org
  end

  before do
    customer.save
    organization.save

    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
    }
  end

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  # ---------------------------------------------------------------------------
  # BLOCKER 7: /billing/api/plans returns {"plans":[]}
  # TC-2309-007
  # ---------------------------------------------------------------------------
  describe 'BLOCKER 7: GET /billing/api/plans' do
    context 'when Stripe plans are configured' do
      it 'returns a non-empty plans array' do
        get '/billing/api/plans'

        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to include('application/json')

        data = JSON.parse(last_response.body)
        expect(data).to have_key('plans')
        expect(data['plans']).to be_an(Array)

        # BLOCKER 7 ASSERTION: plans array should NOT be empty
        expect(data['plans']).not_to be_empty,
          'BLOCKER 7 FAILURE: Plans API returns empty array. ' \
          'Verify Stripe products have show_on_plans_page=true metadata and cache is populated.'
      end

      it 'includes required plan attributes' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        skip 'Plans array empty - cannot verify attributes' if data['plans'].empty?

        plan = data['plans'].first
        expect(plan).to include(
          'id', 'name', 'tier', 'interval', 'amount', 'currency',
          'features', 'limits', 'entitlements'
        )
      end

      it 'includes plans sorted by display_order' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        skip 'Plans array empty' if data['plans'].empty?

        display_orders = data['plans'].map { |p| p['display_order'] }
        expect(display_orders).to eq(display_orders.sort),
          'Plans should be sorted by display_order ascending'
      end
    end
  end

  # ---------------------------------------------------------------------------
  # BLOCKER 1 & 2: Monthly/Yearly plans tabs empty
  # TC-2309-001, TC-2309-002
  # ---------------------------------------------------------------------------
  describe 'BLOCKER 1 & 2: Plans by interval' do
    context 'monthly plans' do
      it 'returns plans with interval=month' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        monthly_plans = data['plans'].select { |p| p['interval'] == 'month' }

        # BLOCKER 1 ASSERTION: Monthly tab should have plans
        expect(monthly_plans).not_to be_empty,
          'BLOCKER 1 FAILURE: No monthly plans available. ' \
          'Verify Stripe prices with interval=month and show_on_plans_page=true.'
      end

      it 'monthly plans have positive amount' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        monthly_plans = data['plans'].select { |p| p['interval'] == 'month' }
        skip 'No monthly plans' if monthly_plans.empty?

        monthly_plans.each do |plan|
          expect(plan['amount']).to be > 0,
            "Plan #{plan['id']} should have positive amount"
        end
      end
    end

    context 'yearly plans' do
      it 'returns plans with interval=year' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        yearly_plans = data['plans'].select { |p| p['interval'] == 'year' }

        # BLOCKER 2 ASSERTION: Yearly tab should have plans
        expect(yearly_plans).not_to be_empty,
          'BLOCKER 2 FAILURE: No yearly plans available. ' \
          'Verify Stripe prices with interval=year and show_on_plans_page=true.'
      end

      it 'yearly plans have annualized amount' do
        get '/billing/api/plans'

        data = JSON.parse(last_response.body)
        yearly_plans = data['plans'].select { |p| p['interval'] == 'year' }
        skip 'No yearly plans' if yearly_plans.empty?

        yearly_plans.each do |plan|
          expect(plan['amount']).to be > 0,
            "Plan #{plan['id']} should have positive annual amount"
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # BLOCKER 8: /billing/api/entitlements/{org_id} returns 500
  # TC-2309-008
  # ---------------------------------------------------------------------------
  describe 'BLOCKER 8: GET /billing/api/entitlements/:extid' do
    context 'with valid organization' do
      it 'returns 200 with entitlements data' do
        get "/billing/api/entitlements/#{organization.extid}"

        # BLOCKER 8 ASSERTION: Should NOT return 500
        expect(last_response.status).not_to eq(500),
          'BLOCKER 8 FAILURE: Entitlements API returns 500. ' \
          'Check organization lookup and entitlement resolution.'

        expect(last_response.status).to eq(200)
        expect(last_response.content_type).to include('application/json')
      end

      it 'includes required entitlement fields' do
        get "/billing/api/entitlements/#{organization.extid}"
        skip 'Entitlements API failing' unless last_response.status == 200

        data = JSON.parse(last_response.body)
        expect(data).to include(
          'planid', 'plan_name', 'entitlements', 'limits', 'is_legacy'
        )
      end

      it 'returns entitlements as array' do
        get "/billing/api/entitlements/#{organization.extid}"
        skip 'Entitlements API failing' unless last_response.status == 200

        data = JSON.parse(last_response.body)
        expect(data['entitlements']).to be_an(Array)
      end

      it 'returns limits as hash' do
        get "/billing/api/entitlements/#{organization.extid}"
        skip 'Entitlements API failing' unless last_response.status == 200

        data = JSON.parse(last_response.body)
        expect(data['limits']).to be_a(Hash)
      end
    end

    context 'with organization that has a plan' do
      let(:test_plan_id) { 'identity_plus_v1_monthly' }

      before do
        organization.planid = test_plan_id
        organization.save
      end

      it 'returns the assigned plan entitlements' do
        get "/billing/api/entitlements/#{organization.extid}"
        skip 'Entitlements API failing' unless last_response.status == 200

        data = JSON.parse(last_response.body)
        expect(data['planid']).to eq(test_plan_id)
        expect(data['entitlements']).not_to be_empty
      end
    end

    context 'with non-member user' do
      let(:other_customer) do
        cust = Onetime::Customer.create!(email: "other-#{SecureRandom.hex(4)}@example.com")
        created_customers << cust
        cust
      end

      before do
        other_customer.save
        env 'rack.session', {
          'authenticated' => true,
          'external_id' => other_customer.extid,
        }
      end

      it 'returns 403 access denied' do
        get "/billing/api/entitlements/#{organization.extid}"

        expect(last_response.status).to eq(403)
        expect(last_response.body).to include('Access denied')
      end
    end

    context 'with non-existent organization' do
      it 'returns 403 organization not found' do
        get '/billing/api/entitlements/nonexistent_org_id'

        expect(last_response.status).to eq(403)
        expect(last_response.body).to include('Organization not found')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Plan cache verification (root cause for blockers 1, 2, 7)
  # ---------------------------------------------------------------------------
  describe 'Plan cache population' do
    it 'Plan.list_plans returns cached plans' do
      plans = ::Billing::Plan.list_plans

      expect(plans).not_to be_empty,
        'Plan cache appears empty. Verify billing initializer runs on boot ' \
        'and Stripe products have correct metadata.'
    end

    it 'plans have show_on_plans_page flag' do
      plans = ::Billing::Plan.list_plans
      skip 'No plans in cache' if plans.empty?

      visible_plans = plans.select { |p| p.show_on_plans_page.to_s == 'true' }
      expect(visible_plans).not_to be_empty,
        'No plans have show_on_plans_page=true. Check Stripe product metadata.'
    end

    it 'plans are retrievable by tier and billing cycle' do
      skip 'Plan cache empty' if ::Billing::Plan.list_plans.empty?

      # Test common tier/billing cycle combinations
      plan = ::Billing::Plan.get_plan('single_team', 'monthly', 'EU')
      expect(plan).not_to be_nil,
        'Could not retrieve single_team monthly plan. ' \
        'Check Plan.get_plan lookup logic and cache keys.'
    end
  end

  # ---------------------------------------------------------------------------
  # Authentication requirement verification
  # ---------------------------------------------------------------------------
  describe 'Authentication requirements' do
    context 'when not authenticated' do
      before do
        env 'rack.session', {}
      end

      it 'plans endpoint is publicly accessible (no auth required)' do
        # Plans listing is intentionally public for pricing page display
        # See routes.txt: GET /api/plans ... auth=noauth
        get '/billing/api/plans'

        expect(last_response.status).to eq(200)
      end

      it 'entitlements endpoint requires authentication' do
        get "/billing/api/entitlements/#{organization.extid}"

        expect(last_response.status).to eq(401)
      end
    end
  end
end

# ---------------------------------------------------------------------------
# BLOCKER 3: /api/v3/receipt/recent returns 403
# TC-2309-003
# This uses the main API app, not the billing app
# ---------------------------------------------------------------------------
RSpec.describe 'BLOCKER 3: Receipt Recent API', :integration, :vcr do
  include Rack::Test::Methods

  # Load the main API v3 app
  def app
    @app ||= begin
      require 'v3/application'
      Rack::URLMap.new('/api/v3' => ::V3::Application.new)
    end
  end

  let(:created_customers) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "receipt-test-#{SecureRandom.hex(4)}@example.com")
    cust.planid = 'identity_v1' # Give user a plan to ensure auth works
    created_customers << cust
    cust
  end

  before do
    customer.save
  end

  after do
    created_customers.each(&:destroy!)
  end

  describe 'GET /api/v3/receipt/recent' do
    context 'with session authentication' do
      before do
        env 'rack.session', {
          'authenticated' => true,
          'external_id' => customer.extid,
        }
      end

      it 'returns 200 for authenticated users' do
        get '/api/v3/receipt/recent'

        # BLOCKER 3 ASSERTION: Should NOT return 403
        expect(last_response.status).not_to eq(403),
          'BLOCKER 3 FAILURE: Receipt recent API returns 403 for authenticated user. ' \
          'Check session authentication middleware and auth strategy.'

        expect([200, 204]).to include(last_response.status),
          "Expected 200 or 204, got #{last_response.status}: #{last_response.body}"
      end

      it 'returns valid JSON response' do
        get '/api/v3/receipt/recent'
        skip 'Receipt API failing' unless [200, 204].include?(last_response.status)

        if last_response.status == 200
          expect(last_response.content_type).to include('application/json')
          data = JSON.parse(last_response.body)
          expect(data).to have_key('records')
        end
      end
    end

    context 'without authentication' do
      before do
        env 'rack.session', {}
      end

      it 'returns 401 for unauthenticated requests' do
        get '/api/v3/receipt/recent'

        expect(last_response.status).to eq(401),
          'Expected 401 for unauthenticated request, not 403'
      end
    end
  end
end
