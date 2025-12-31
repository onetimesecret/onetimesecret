# apps/web/billing/spec/controllers/plan_switching_spec.rb
#
# frozen_string_literal: true

# Test coverage for plan switching workflow - covers fixes made 2025-12-31:
# 1. Stripe API key loading via autodiscover filter (billing.* namespace)
# 2. Invoice.create_preview API (subscription at top level, subscription_details for items)
# 3. Proration detection via parent.subscription_item_details.proration
# 4. Price object handling (String ID vs Price object)

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'
require 'digest'

require_relative '../../application'

RSpec.describe 'Plan Switching Workflow', :integration do
  include Rack::Test::Methods

  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  # Deterministic email for VCR cassette matching
  def deterministic_email(prefix = 'plan-switch-test')
    test_hash = Digest::SHA256.hexdigest(RSpec.current_example.full_description)[0..7]
    "#{prefix}-#{test_hash}@example.com"
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: deterministic_email)
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
    mock_region!('EU')

    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
    }
  end

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  # ===========================================================================
  # MOCK BUILDERS - New Stripe API structure (2023+)
  # ===========================================================================

  def build_mock_price(attrs = {})
    double('Stripe::Price', {
      id: 'price_test123',
      product: 'prod_test123',
      unit_amount: 1000,
      currency: 'cad',
      recurring: double('Recurring', interval: 'month', interval_count: 1),
      metadata: {},
    }.merge(attrs))
  end

  def build_mock_subscription_item(attrs = {})
    price = attrs.delete(:price) || build_mock_price
    double('Stripe::SubscriptionItem', {
      id: 'si_test123',
      price: price,
      quantity: 1,
      current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
    }.merge(attrs))
  end

  def build_mock_subscription(attrs = {})
    items_data = attrs.delete(:items) || [build_mock_subscription_item]

    subscription_items = double('Stripe::ListObject',
                                data: items_data,
                                first: items_data.first,
                                map: ->(block = nil, &blk) { items_data.map(&(block || blk)) },
                                each: ->(block = nil, &blk) { items_data.each(&(block || blk)) })

    double('Stripe::Subscription', {
      id: 'sub_test123',
      status: 'active',
      customer: 'cus_test123',
      current_period_start: Time.now.to_i,
      current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i,
      items: subscription_items,
      metadata: {},
      cancel_at_period_end: false,
      canceled_at: nil,
    }.merge(attrs))
  end

  # Build invoice preview line item with NEW parent structure
  def build_mock_preview_line_item(type:, amount: nil, price_id: nil)
    # New Stripe API: proration flag is in parent.subscription_item_details
    subscription_item_details = double('SubscriptionItemDetails',
                                       proration: %i[credit proration].include?(type))

    parent = double('Parent',
                    subscription_item_details: subscription_item_details,
                    invoice_item_details: nil)

    calculated_amount = case type
                        when :credit then amount || -500
                        when :charge then amount || 1000
                        when :proration then amount || -300
                        else amount || 0
                        end

    # Price can be object or string - test both
    price_value = price_id || build_mock_price

    double('Stripe::InvoiceLineItem', {
      id: "il_#{SecureRandom.hex(8)}",
      amount: calculated_amount,
      currency: 'cad',
      description: type == :credit ? 'Unused time' : 'Remaining time',
      parent: parent,
      price: price_value,
      pricing: double('Pricing', price_details: double('PriceDetails', price: price_value)),
      period: double('Period',
                     start: Time.now.to_i,
                     end: (Time.now + 30 * 24 * 60 * 60).to_i),
    })
  end

  def build_mock_invoice_preview(attrs = {})
    line_items = attrs.delete(:lines) || [
      build_mock_preview_line_item(type: :credit, amount: -500),
      build_mock_preview_line_item(type: :charge, amount: 1500),
    ]

    lines_object = double('Stripe::ListObject',
                          data: line_items,
                          each: ->(block = nil, &blk) { line_items.each(&(block || blk)) },
                          map: ->(block = nil, &blk) { line_items.map(&(block || blk)) },
                          select: ->(block = nil, &blk) { line_items.select(&(block || blk)) },
                          sum: ->(&blk) { line_items.sum(&blk) })

    double('Stripe::Invoice', {
      id: nil, # Previews don't have ID
      subtotal: line_items.sum(&:amount),
      total: line_items.sum(&:amount),
      amount_due: line_items.sum(&:amount),
      currency: 'cad',
      lines: lines_object,
      next_payment_attempt: (Time.now + 30 * 24 * 60 * 60).to_i,
    }.merge(attrs))
  end

  # ===========================================================================
  # SCENARIO 1: FREE PLAN USER (NO SUBSCRIPTION) → CHECKOUT
  # ===========================================================================
  describe 'Scenario 1: Free user - subscription status' do
    describe 'GET /billing/api/org/:extid/subscription' do
      context 'when user has no subscription' do
        it 'returns has_active_subscription: false' do
          get "/billing/api/org/#{organization.extid}/subscription"

          expect(last_response.status).to eq(200)
          data = JSON.parse(last_response.body)
          expect(data['has_active_subscription']).to eq(false)
        end

        it 'returns current_plan from organization' do
          organization.planid = 'free_v1'
          organization.save

          get "/billing/api/org/#{organization.extid}/subscription"

          expect(last_response.status).to eq(200)
          data = JSON.parse(last_response.body)
          expect(data['current_plan']).to eq('free_v1')
        end

        it 'does not call Stripe API when no subscription ID exists' do
          expect(Stripe::Subscription).not_to receive(:retrieve)

          get "/billing/api/org/#{organization.extid}/subscription"

          expect(last_response.status).to eq(200)
        end
      end
    end
  end

  # ===========================================================================
  # SCENARIO 2: EXISTING SUBSCRIBER → UPGRADE TO HIGHER TIER
  # ===========================================================================
  describe 'Scenario 2: Existing subscriber upgrading plan' do
    let(:current_price_id) { 'price_identity_plus_monthly' }
    let(:new_price_id) { 'price_single_team_monthly' }
    let(:current_price) { build_mock_price(id: current_price_id, unit_amount: 1900) }
    let(:new_price) { build_mock_price(id: new_price_id, unit_amount: 4900) }
    let(:subscription_item) { build_mock_subscription_item(id: 'si_current', price: current_price) }
    let(:mock_subscription) { build_mock_subscription(id: 'sub_active', items: [subscription_item]) }

    before do
      organization.stripe_subscription_id = 'sub_active'
      organization.stripe_customer_id = 'cus_active'
      organization.planid = 'identity_plus_v1_monthly'
      organization.subscription_status = 'active'
      organization.save
    end

    # -------------------------------------------------------------------------
    # 2A: SUBSCRIPTION STATUS
    # -------------------------------------------------------------------------
    describe 'GET /billing/api/org/:extid/subscription (with active subscription)' do
      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_active')
          .and_return(mock_subscription)
      end

      it 'returns has_active_subscription: true' do
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['has_active_subscription']).to eq(true)
      end

      it 'returns current_price_id from Stripe subscription' do
        get "/billing/api/org/#{organization.extid}/subscription"

        data = JSON.parse(last_response.body)
        expect(data['current_price_id']).to eq(current_price_id)
      end

      it 'returns subscription_item_id for plan changes' do
        get "/billing/api/org/#{organization.extid}/subscription"

        data = JSON.parse(last_response.body)
        expect(data['subscription_item_id']).to eq('si_current')
      end

      context 'when Stripe API key is missing' do
        before do
          allow(Stripe).to receive(:api_key).and_return(nil)
        end

        it 'returns 503 with billing unavailable message' do
          get "/billing/api/org/#{organization.extid}/subscription"

          expect(last_response.status).to eq(503)
          data = JSON.parse(last_response.body)
          expect(data['error']).to include('unavailable')
        end
      end
    end

    # -------------------------------------------------------------------------
    # 2B: PRORATION PREVIEW
    # -------------------------------------------------------------------------
    describe 'POST /billing/api/org/:extid/preview-plan-change' do
      let(:mock_preview) do
        build_mock_invoice_preview(
          lines: [
            build_mock_preview_line_item(type: :credit, amount: -950, price_id: new_price),
            build_mock_preview_line_item(type: :charge, amount: 2450, price_id: new_price),
          ],
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_active')
          .and_return(mock_subscription)

        allow(Stripe::Invoice).to receive(:create_preview)
          .and_return(mock_preview)

        allow(Stripe::Price).to receive(:retrieve)
          .with(new_price_id)
          .and_return(new_price)

        # Mock the plan catalog lookup
        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly'))
      end

      context 'input validation' do
        it 'returns 400 when new_price_id is missing' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change", {}

          expect(last_response.status).to eq(400)
          data = JSON.parse(last_response.body)
          expect(data['error']).to include('Missing')
        end

        it 'returns 400 when switching to same price' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: current_price_id }

          expect(last_response.status).to eq(400)
          data = JSON.parse(last_response.body)
          expect(data['error']).to include('Already on this plan')
        end
      end

      context 'with valid upgrade request' do
        it 'calls Invoice.create_preview with correct API structure' do
          expect(Stripe::Invoice).to receive(:create_preview).with(
            hash_including(
              customer: 'cus_active',
              subscription: 'sub_active',
              subscription_details: hash_including(
                items: array_including(
                  hash_including(id: 'si_current', price: new_price_id),
                ),
                proration_behavior: 'create_prorations',
              ),
            ),
          ).and_return(mock_preview)

          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(200)
        end

        it 'returns amount_due from preview' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          expect(data['amount_due']).to eq(1500) # 2450 - 950
        end

        it 'calculates credit_applied from proration items' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          expect(data['credit_applied']).to eq(950) # abs of -950
        end

        it 'returns new_plan details' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          expect(data['new_plan']['price_id']).to eq(new_price_id)
          expect(data['new_plan']['amount']).to eq(4900)
        end
      end

      context 'when Stripe API key is missing' do
        before do
          allow(Stripe).to receive(:api_key).and_return(nil)
        end

        it 'returns 503 before making Stripe API calls' do
          expect(Stripe::Invoice).not_to receive(:create_preview)

          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(503)
        end
      end
    end

    # -------------------------------------------------------------------------
    # 2C: EXECUTE PLAN CHANGE
    # -------------------------------------------------------------------------
    describe 'POST /billing/api/org/:extid/change-plan' do
      let(:updated_subscription_item) { build_mock_subscription_item(id: 'si_current', price: new_price) }
      let(:updated_subscription) { build_mock_subscription(id: 'sub_active', items: [updated_subscription_item]) }

      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_active')
          .and_return(mock_subscription)

        allow(Stripe::Subscription).to receive(:update)
          .and_return(updated_subscription)

        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly'))

        # Stub update_from_stripe_subscription to avoid type validation on mock
        allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
          .and_return(true)
      end

      context 'input validation' do
        it 'returns 400 when new_price_id is missing' do
          post "/billing/api/org/#{organization.extid}/change-plan", {}

          expect(last_response.status).to eq(400)
        end
      end

      context 'with valid plan change request' do
        it 'calls Subscription.update with correct parameters' do
          expect(Stripe::Subscription).to receive(:update).with(
            'sub_active',
            hash_including(
              items: array_including(
                hash_including(id: 'si_current', price: new_price_id),
              ),
              proration_behavior: 'create_prorations',
            ),
            hash_including(:idempotency_key),
          ).and_return(updated_subscription)

          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(200)
        end

        it 'returns success with subscription status' do
          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          expect(data['success']).to eq(true)
          expect(data['status']).to eq('active')
        end
      end

      context 'when Stripe API key is missing' do
        before do
          allow(Stripe).to receive(:api_key).and_return(nil)
        end

        it 'returns 503 before making Stripe API calls' do
          expect(Stripe::Subscription).not_to receive(:update)

          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(503)
        end
      end
    end
  end

  # ===========================================================================
  # HELPER METHOD TESTS
  # ===========================================================================
  describe 'Helper methods' do
    describe 'line_is_proration? (new Stripe API structure)' do
      let(:controller) { Billing::Controllers::BillingController.allocate }

      context 'with subscription_item_details.proration = true' do
        it 'returns true' do
          line = build_mock_preview_line_item(type: :proration)
          result = controller.send(:line_is_proration?, line)
          expect(result).to be true
        end
      end

      context 'with subscription_item_details.proration = false' do
        it 'returns false' do
          line = build_mock_preview_line_item(type: :charge)
          result = controller.send(:line_is_proration?, line)
          expect(result).to be false
        end
      end

      context 'when parent is nil' do
        it 'returns false' do
          line = double('InvoiceLineItem', parent: nil)
          result = controller.send(:line_is_proration?, line)
          expect(result).to be false
        end
      end
    end
  end

  # ===========================================================================
  # AUTHORIZATION TESTS
  # ===========================================================================
  describe 'Authorization' do
    describe 'when not authenticated' do
      before do
        env 'rack.session', {}
      end

      it 'returns 401 for subscription_status' do
        get "/billing/api/org/#{organization.extid}/subscription"
        expect(last_response.status).to eq(401)
      end

      it 'returns 401 for preview-plan-change' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: 'price_test' }
        expect(last_response.status).to eq(401)
      end

      it 'returns 401 for change-plan' do
        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: 'price_test' }
        expect(last_response.status).to eq(401)
      end
    end

    describe 'when user is not organization member' do
      let(:other_customer) do
        cust = Onetime::Customer.create!(email: 'other@example.com')
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

      it 'returns 403 for subscription_status' do
        get "/billing/api/org/#{organization.extid}/subscription"
        expect(last_response.status).to eq(403)
      end
    end
  end
end
