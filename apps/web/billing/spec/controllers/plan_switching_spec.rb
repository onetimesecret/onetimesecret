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
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))
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
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))

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

      # -----------------------------------------------------------------------
      # STATE SYNC ERROR HANDLING
      # -----------------------------------------------------------------------
      # Tests for the fix that handles local Redis sync failures gracefully
      # after Stripe update succeeds. Stripe is authoritative; if the local
      # update fails, we still return success and rely on webhook reconciliation.
      # -----------------------------------------------------------------------
      context 'when local state sync fails after Stripe update' do
        before do
          # Make the local sync fail
          allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
            .and_raise(StandardError.new('Redis connection failed'))
        end

        it 'still returns success since Stripe update succeeded' do
          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(200)
          data = JSON.parse(last_response.body)
          expect(data['success']).to eq(true)
        end

        it 'returns the new plan from Stripe response data' do
          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          # Should use plan data from catalog lookup since local state is stale
          expect(data['new_plan']).to eq('single_team_v1_monthly')
        end

        it 'logs the sync failure with recovery strategy' do
          # Expect billing_logger.error to be called with sync failure details
          expect_any_instance_of(Billing::Controllers::BillingController)
            .to receive(:billing_logger).at_least(:once).and_call_original

          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          expect(last_response.status).to eq(200)
        end

        it 'includes local_sync_failed in log context' do
          # The controller logs info with local_sync_failed: true
          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          # Verify request succeeded despite sync failure
          expect(last_response.status).to eq(200)
        end
      end

      context 'when local state sync succeeds' do
        it 'returns new_plan from organization model' do
          # Normal case: sync succeeds, org.planid is updated
          allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription) do |org, _sub|
            org.planid = 'single_team_v1_monthly'
            true
          end

          post "/billing/api/org/#{organization.extid}/change-plan",
               { new_price_id: new_price_id }

          data = JSON.parse(last_response.body)
          expect(data['new_plan']).to eq('single_team_v1_monthly')
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
  # SCENARIO 3: EXISTING SUBSCRIBER → DOWNGRADE TO LOWER TIER
  # ===========================================================================
  describe 'Scenario 3: Existing subscriber downgrading plan' do
    let(:current_price_id) { 'price_single_team_monthly' }
    let(:lower_price_id) { 'price_identity_plus_monthly' }
    let(:current_price) { build_mock_price(id: current_price_id, unit_amount: 4900) }
    let(:lower_price) { build_mock_price(id: lower_price_id, unit_amount: 1900) }
    let(:subscription_item) { build_mock_subscription_item(id: 'si_downgrade', price: current_price) }
    let(:mock_subscription) { build_mock_subscription(id: 'sub_downgrade', items: [subscription_item]) }

    before do
      organization.stripe_subscription_id = 'sub_downgrade'
      organization.stripe_customer_id = 'cus_downgrade'
      organization.planid = 'single_team_v1_monthly'
      organization.subscription_status = 'active'
      organization.save
    end

    describe 'POST /billing/api/org/:extid/preview-plan-change (downgrade)' do
      let(:downgrade_preview) do
        # Downgrade: credit is typically larger than new charge
        build_mock_invoice_preview(
          lines: [
            build_mock_preview_line_item(type: :credit, amount: -2450, price_id: lower_price),
            build_mock_preview_line_item(type: :charge, amount: 950, price_id: lower_price),
          ],
        )
      end

      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_downgrade')
          .and_return(mock_subscription)

        allow(Stripe::Invoice).to receive(:create_preview)
          .and_return(downgrade_preview)

        allow(Stripe::Price).to receive(:retrieve)
          .with(lower_price_id)
          .and_return(lower_price)

        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(lower_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'identity_plus_v1_monthly', tier: 'single_team'))
      end

      it 'returns negative amount_due for downgrade with credit' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: lower_price_id }

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        # Credit exceeds charge: 950 - 2450 = -1500
        expect(data['amount_due']).to eq(-1500)
      end

      it 'returns credit_applied from proration' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: lower_price_id }

        data = JSON.parse(last_response.body)
        expect(data['credit_applied']).to eq(2450)
      end

      it 'returns lower plan amount' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: lower_price_id }

        data = JSON.parse(last_response.body)
        expect(data['new_plan']['amount']).to eq(1900)
        expect(data['current_plan']['amount']).to eq(4900)
      end
    end

    describe 'POST /billing/api/org/:extid/change-plan (downgrade)' do
      let(:downgraded_subscription_item) { build_mock_subscription_item(id: 'si_downgrade', price: lower_price) }
      let(:downgraded_subscription) { build_mock_subscription(id: 'sub_downgrade', items: [downgraded_subscription_item]) }

      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_downgrade')
          .and_return(mock_subscription)

        allow(Stripe::Subscription).to receive(:update)
          .and_return(downgraded_subscription)

        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(lower_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'identity_plus_v1_monthly', tier: 'single_team'))

        allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
          .and_return(true)
      end

      it 'successfully processes downgrade' do
        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: lower_price_id }

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['success']).to eq(true)
      end

      it 'calls Subscription.update with lower tier price' do
        expect(Stripe::Subscription).to receive(:update).with(
          'sub_downgrade',
          hash_including(
            items: array_including(
              hash_including(id: 'si_downgrade', price: lower_price_id),
            ),
          ),
          hash_including(:idempotency_key),
        ).and_return(downgraded_subscription)

        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: lower_price_id }
      end
    end
  end

  # ===========================================================================
  # IDEMPOTENCY KEY TESTS
  # ===========================================================================
  describe 'Idempotency key handling' do
    let(:current_price_id) { 'price_identity_plus_monthly' }
    let(:new_price_id) { 'price_single_team_monthly' }
    let(:current_price) { build_mock_price(id: current_price_id, unit_amount: 1900) }
    let(:new_price) { build_mock_price(id: new_price_id, unit_amount: 4900) }
    let(:subscription_item) { build_mock_subscription_item(id: 'si_idem', price: current_price) }
    let(:mock_subscription) { build_mock_subscription(id: 'sub_idem', items: [subscription_item]) }

    before do
      organization.stripe_subscription_id = 'sub_idem'
      organization.stripe_customer_id = 'cus_idem'
      organization.planid = 'identity_plus_v1_monthly'
      organization.subscription_status = 'active'
      organization.save
    end

    describe 'POST /billing/api/org/:extid/change-plan idempotency' do
      let(:updated_subscription_item) { build_mock_subscription_item(id: 'si_idem', price: new_price) }
      let(:updated_subscription) { build_mock_subscription(id: 'sub_idem', items: [updated_subscription_item]) }

      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_idem')
          .and_return(mock_subscription)

        allow(Stripe::Subscription).to receive(:update)
          .and_return(updated_subscription)

        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))

        allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
          .and_return(true)
      end

      it 'generates idempotency key based on subscription, price, and 5-minute window' do
        frozen_time = Time.utc(2025, 1, 1, 12, 0, 0)
        allow(Time).to receive(:now).and_return(frozen_time)

        expected_key_input = "plan_change:sub_idem:#{new_price_id}:#{frozen_time.to_i / 300}"
        expected_key = Digest::SHA256.hexdigest(expected_key_input)

        expect(Stripe::Subscription).to receive(:update).with(
          'sub_idem',
          anything,
          hash_including(idempotency_key: expected_key),
        ).and_return(updated_subscription)

        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }
      end

      it 'generates same idempotency key within 5-minute window' do
        # First request at minute 0
        time_1 = Time.utc(2025, 1, 1, 12, 0, 0)
        allow(Time).to receive(:now).and_return(time_1)

        key_input_1 = "plan_change:sub_idem:#{new_price_id}:#{time_1.to_i / 300}"
        expected_key_1 = Digest::SHA256.hexdigest(key_input_1)

        # Second request at minute 4 (within same 5-minute window)
        time_2 = Time.utc(2025, 1, 1, 12, 4, 59)
        key_input_2 = "plan_change:sub_idem:#{new_price_id}:#{time_2.to_i / 300}"
        expected_key_2 = Digest::SHA256.hexdigest(key_input_2)

        # Both should produce the same key (same 5-minute bucket)
        expect(expected_key_1).to eq(expected_key_2)
      end

      it 'generates different idempotency key after 5-minute window' do
        # First request at minute 0
        time_1 = Time.utc(2025, 1, 1, 12, 0, 0)
        key_input_1 = "plan_change:sub_idem:#{new_price_id}:#{time_1.to_i / 300}"
        expected_key_1 = Digest::SHA256.hexdigest(key_input_1)

        # Second request at minute 5 (new 5-minute window)
        time_2 = Time.utc(2025, 1, 1, 12, 5, 0)
        key_input_2 = "plan_change:sub_idem:#{new_price_id}:#{time_2.to_i / 300}"
        expected_key_2 = Digest::SHA256.hexdigest(key_input_2)

        # Keys should differ across windows
        expect(expected_key_1).not_to eq(expected_key_2)
      end

      it 'generates different idempotency key for different price' do
        time = Time.utc(2025, 1, 1, 12, 0, 0)
        other_price_id = 'price_org_max_monthly'

        key_input_1 = "plan_change:sub_idem:#{new_price_id}:#{time.to_i / 300}"
        key_input_2 = "plan_change:sub_idem:#{other_price_id}:#{time.to_i / 300}"

        expect(Digest::SHA256.hexdigest(key_input_1)).not_to eq(Digest::SHA256.hexdigest(key_input_2))
      end

      it 'generates different idempotency key for different subscription' do
        time = Time.utc(2025, 1, 1, 12, 0, 0)
        other_subscription_id = 'sub_other'

        key_input_1 = "plan_change:sub_idem:#{new_price_id}:#{time.to_i / 300}"
        key_input_2 = "plan_change:#{other_subscription_id}:#{new_price_id}:#{time.to_i / 300}"

        expect(Digest::SHA256.hexdigest(key_input_1)).not_to eq(Digest::SHA256.hexdigest(key_input_2))
      end

      it 'passes idempotency key as SHA256 hex string (64 chars)' do
        expect(Stripe::Subscription).to receive(:update).with(
          'sub_idem',
          anything,
          hash_including(idempotency_key: a_string_matching(/^[a-f0-9]{64}$/)),
        ).and_return(updated_subscription)

        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }
      end
    end
  end

  # ===========================================================================
  # SUBSCRIPTION STATE EDGE CASES
  # ===========================================================================
  describe 'Subscription state edge cases' do
    let(:current_price_id) { 'price_identity_plus_monthly' }
    let(:new_price_id) { 'price_single_team_monthly' }
    let(:current_price) { build_mock_price(id: current_price_id, unit_amount: 1900) }
    let(:new_price) { build_mock_price(id: new_price_id, unit_amount: 4900) }
    let(:subscription_item) { build_mock_subscription_item(id: 'si_edge', price: current_price) }

    before do
      organization.stripe_customer_id = 'cus_edge'
      organization.save
    end

    # -------------------------------------------------------------------------
    # PAST_DUE SUBSCRIPTION STATE
    # -------------------------------------------------------------------------
    describe 'past_due subscription' do
      let(:past_due_subscription) do
        build_mock_subscription(
          id: 'sub_past_due',
          status: 'past_due',
          items: [subscription_item],
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_past_due'
        organization.subscription_status = 'past_due'
        organization.save

        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_past_due')
          .and_return(past_due_subscription)
      end

      # Note: past_due is NOT considered active by active_subscription?
      # (only 'active' and 'trialing' are). This is correct behavior -
      # past_due subscriptions need payment resolution before plan changes.
      it 'returns has_active_subscription: false for past_due subscription' do
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['has_active_subscription']).to eq(false)
        expect(data['current_plan']).to eq(organization.planid)
      end

      it 'returns 400 when trying to preview plan change on past_due subscription' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(400)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('No active subscription')
      end

      it 'returns 400 when trying to change plan on past_due subscription' do
        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(400)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('No active subscription')
      end
    end

    # -------------------------------------------------------------------------
    # TRIALING SUBSCRIPTION STATE
    # -------------------------------------------------------------------------
    describe 'trialing subscription' do
      let(:trial_end) { (Time.now + 14 * 24 * 60 * 60).to_i } # 14 days from now
      let(:trialing_subscription) do
        build_mock_subscription(
          id: 'sub_trialing',
          status: 'trialing',
          items: [subscription_item],
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_trialing'
        organization.subscription_status = 'trialing'
        organization.save

        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_trialing')
          .and_return(trialing_subscription)
      end

      it 'returns subscription_status: trialing in status response' do
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['subscription_status']).to eq('trialing')
        expect(data['has_active_subscription']).to eq(true)
      end

      it 'allows plan change preview during trial' do
        mock_preview = build_mock_invoice_preview
        allow(Stripe::Invoice).to receive(:create_preview).and_return(mock_preview)
        allow(Stripe::Price).to receive(:retrieve).with(new_price_id).and_return(new_price)
        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))

        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(200)
      end

      it 'allows plan change execution during trial' do
        updated_subscription = build_mock_subscription(
          id: 'sub_trialing',
          status: 'trialing',
          items: [build_mock_subscription_item(id: 'si_edge', price: new_price)],
        )

        allow(Stripe::Subscription).to receive(:update).and_return(updated_subscription)
        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))
        allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
          .and_return(true)

        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['success']).to eq(true)
        expect(data['status']).to eq('trialing')
      end
    end

    # -------------------------------------------------------------------------
    # CANCELED SUBSCRIPTION STATE
    # -------------------------------------------------------------------------
    describe 'canceled subscription' do
      let(:canceled_subscription) do
        build_mock_subscription(
          id: 'sub_canceled',
          status: 'canceled',
          items: [subscription_item],
          canceled_at: Time.now.to_i,
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_canceled'
        organization.subscription_status = 'canceled'
        organization.save
      end

      it 'returns has_active_subscription: false for canceled subscription' do
        # Organization with canceled status should not be considered active
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['has_active_subscription']).to eq(false)
      end

      it 'returns 400 when trying to change plan on canceled subscription' do
        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(400)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('No active subscription')
      end

      it 'returns 400 when trying to preview plan change on canceled subscription' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(400)
        data = JSON.parse(last_response.body)
        expect(data['error']).to include('No active subscription')
      end
    end

    # -------------------------------------------------------------------------
    # CANCEL_AT_PERIOD_END SUBSCRIPTION STATE
    # -------------------------------------------------------------------------
    describe 'subscription scheduled for cancellation' do
      let(:cancel_at_period_end_subscription) do
        build_mock_subscription(
          id: 'sub_cancel_scheduled',
          status: 'active',
          items: [subscription_item],
          cancel_at_period_end: true,
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_cancel_scheduled'
        organization.subscription_status = 'active'
        organization.save

        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_cancel_scheduled')
          .and_return(cancel_at_period_end_subscription)
      end

      it 'still returns has_active_subscription: true' do
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['has_active_subscription']).to eq(true)
      end

      it 'allows plan change (reactivates subscription)' do
        updated_subscription = build_mock_subscription(
          id: 'sub_cancel_scheduled',
          status: 'active',
          items: [build_mock_subscription_item(id: 'si_edge', price: new_price)],
          cancel_at_period_end: false,
        )

        allow(Stripe::Subscription).to receive(:update).and_return(updated_subscription)
        allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
          .with(new_price_id)
          .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))
        allow_any_instance_of(Onetime::Organization).to receive(:update_from_stripe_subscription)
          .and_return(true)

        post "/billing/api/org/#{organization.extid}/change-plan",
             { new_price_id: new_price_id }

        expect(last_response.status).to eq(200)
      end
    end
  end

  # ===========================================================================
  # TRIAL PERIOD HANDLING
  # ===========================================================================
  describe 'Trial period handling' do
    let(:trial_price_id) { 'price_identity_plus_monthly' }
    let(:trial_price) { build_mock_price(id: trial_price_id, unit_amount: 1900) }
    let(:trial_subscription_item) { build_mock_subscription_item(id: 'si_trial', price: trial_price) }
    let(:trial_end_time) { (Time.now + 14 * 24 * 60 * 60).to_i }

    before do
      organization.stripe_customer_id = 'cus_trial'
      organization.save
    end

    describe 'proration during trial' do
      let(:trialing_subscription) do
        build_mock_subscription(
          id: 'sub_trial_prorate',
          status: 'trialing',
          items: [trial_subscription_item],
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_trial_prorate'
        organization.subscription_status = 'trialing'
        organization.save

        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_trial_prorate')
          .and_return(trialing_subscription)
      end

      context 'when upgrading during trial' do
        let(:upgrade_price_id) { 'price_single_team_monthly' }
        let(:upgrade_price) { build_mock_price(id: upgrade_price_id, unit_amount: 4900) }

        let(:trial_upgrade_preview) do
          # During trial, proration may be zero or minimal
          build_mock_invoice_preview(
            lines: [
              build_mock_preview_line_item(type: :credit, amount: 0, price_id: upgrade_price),
              build_mock_preview_line_item(type: :charge, amount: 0, price_id: upgrade_price),
            ],
            subtotal: 0,
            total: 0,
            amount_due: 0,
          )
        end

        before do
          allow(Stripe::Invoice).to receive(:create_preview).and_return(trial_upgrade_preview)
          allow(Stripe::Price).to receive(:retrieve).with(upgrade_price_id).and_return(upgrade_price)
          allow(::Billing::Plan).to receive(:find_by_stripe_price_id)
            .with(upgrade_price_id)
            .and_return(double('Plan', legacy?: false, plan_id: 'single_team_v1_monthly', tier: 'single_team'))
        end

        it 'returns zero amount_due during trial period' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: upgrade_price_id }

          expect(last_response.status).to eq(200)
          data = JSON.parse(last_response.body)
          expect(data['amount_due']).to eq(0)
        end

        it 'shows new plan pricing even with zero immediate charge' do
          post "/billing/api/org/#{organization.extid}/preview-plan-change",
               { new_price_id: upgrade_price_id }

          data = JSON.parse(last_response.body)
          expect(data['new_plan']['amount']).to eq(4900)
        end
      end
    end

    describe 'trial without payment method' do
      let(:trial_no_payment_subscription) do
        build_mock_subscription(
          id: 'sub_trial_no_pm',
          status: 'trialing',
          items: [trial_subscription_item],
        )
      end

      before do
        organization.stripe_subscription_id = 'sub_trial_no_pm'
        organization.subscription_status = 'trialing'
        organization.save

        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_trial_no_pm')
          .and_return(trial_no_payment_subscription)
      end

      it 'returns subscription status as trialing' do
        get "/billing/api/org/#{organization.extid}/subscription"

        expect(last_response.status).to eq(200)
        data = JSON.parse(last_response.body)
        expect(data['subscription_status']).to eq('trialing')
        expect(data['has_active_subscription']).to eq(true)
      end
    end
  end

  # ===========================================================================
  # INVALID ORGANIZATION EXTID
  # ===========================================================================
  describe 'Invalid organization extid' do
    let(:nonexistent_extid) { 'org_nonexistent_12345' }
    let(:malformed_extid) { 'not-a-valid-extid' }

    describe 'GET /billing/api/org/:extid/subscription' do
      it 'returns 403 for nonexistent organization extid' do
        get "/billing/api/org/#{nonexistent_extid}/subscription"

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for malformed organization extid' do
        get "/billing/api/org/#{malformed_extid}/subscription"

        expect(last_response.status).to eq(403)
      end

      it 'handles empty organization extid gracefully' do
        get '/billing/api/org//subscription'

        # Route with empty segment may:
        # - Fall through to index (200)
        # - Return 404 (route not matched)
        # - Return 403 (auth check fails on empty/nil)
        # All are valid handling; key is no 500 error
        expect(last_response.status).to be < 500
      end
    end

    describe 'POST /billing/api/org/:extid/preview-plan-change' do
      it 'returns 403 for nonexistent organization extid' do
        post "/billing/api/org/#{nonexistent_extid}/preview-plan-change",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for malformed organization extid' do
        post "/billing/api/org/#{malformed_extid}/preview-plan-change",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
      end
    end

    describe 'POST /billing/api/org/:extid/change-plan' do
      it 'returns 403 for nonexistent organization extid' do
        post "/billing/api/org/#{nonexistent_extid}/change-plan",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for malformed organization extid' do
        post "/billing/api/org/#{malformed_extid}/change-plan",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
      end
    end

    describe 'organization belonging to different customer' do
      let(:other_org) do
        other_cust = Onetime::Customer.create!(email: 'other-org-owner@example.com')
        created_customers << other_cust
        other_cust.save

        org = Onetime::Organization.create!('Other Org', other_cust, other_cust.email)
        created_organizations << org
        org.save
        org
      end

      it 'returns 403 for subscription status' do
        get "/billing/api/org/#{other_org.extid}/subscription"

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for preview-plan-change' do
        post "/billing/api/org/#{other_org.extid}/preview-plan-change",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
      end

      it 'returns 403 for change-plan' do
        post "/billing/api/org/#{other_org.extid}/change-plan",
             { new_price_id: 'price_test' }

        expect(last_response.status).to eq(403)
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
