# apps/web/billing/spec/operations/process_webhook_event/catalog_updates_spec.rb
#
# frozen_string_literal: true

# Tests for product/price catalog update webhook events.
# These events now use incremental sync instead of full catalog refresh.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/catalog_updates_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'
require_relative '../../../models/stripe_webhook_event'

RSpec.describe 'ProcessWebhookEvent: catalog updates', :integration, :process_webhook_event do
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  # OTS product with proper metadata
  let(:ots_product) do
    build_stripe_product(
      id: 'prod_ots_123',
      name: 'Identity Plus',
      metadata: { 'app' => 'onetimesecret', 'tier' => 'identity_plus', 'region' => 'v1' }
    )
  end

  # Non-OTS product (should be ignored)
  let(:other_product) do
    build_stripe_product(
      id: 'prod_other_456',
      name: 'Other Product',
      metadata: { 'app' => 'other_app' }
    )
  end

  # Recurring price for OTS product
  let(:recurring_price) do
    Stripe::Price.construct_from({
      id: 'price_ots_monthly',
      object: 'price',
      product: 'prod_ots_123',
      type: 'recurring',
      active: true,
      unit_amount: 1900,
      currency: 'cad',
      billing_scheme: 'per_unit',
      recurring: {
        interval: 'month',
        interval_count: 1,
        usage_type: 'licensed',
      },
    })
  end

  # One-time price (should be skipped)
  let(:one_time_price) do
    Stripe::Price.construct_from({
      id: 'price_one_time',
      object: 'price',
      product: 'prod_ots_123',
      type: 'one_time',
      active: true,
      unit_amount: 500,
      currency: 'cad',
    })
  end

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe 'product events (incremental sync)' do
    describe 'product.created' do
      let(:event) { build_stripe_event(type: 'product.created', data_object: ots_product) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        # Stub Stripe API calls - handler fetches fresh data
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)

        # Return recurring price list
        price_list = instance_double(Stripe::ListObject)
        allow(price_list).to receive(:auto_paging_each).and_yield(recurring_price)
        allow(Stripe::Price).to receive(:list).with(product: 'prod_ots_123', active: true).and_return(price_list)

        # Stub upsert methods
        allow(Billing::Plan).to receive(:extract_plan_data).and_return({ plan_id: 'test_plan' })
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
      end

      include_examples 'handles event successfully'

      it 'fetches fresh product from Stripe' do
        operation.call
        expect(Stripe::Product).to have_received(:retrieve).with('prod_ots_123')
      end

      it 'fetches active prices for the product' do
        operation.call
        expect(Stripe::Price).to have_received(:list).with(product: 'prod_ots_123', active: true)
      end

      it 'upserts plan data for recurring prices' do
        operation.call
        expect(Billing::Plan).to have_received(:upsert_from_stripe_data)
      end

      it 'rebuilds the price ID cache' do
        operation.call
        expect(Billing::Plan).to have_received(:rebuild_stripe_price_id_cache)
      end

      it 'does NOT call full refresh_from_stripe' do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
        operation.call
        expect(Billing::Plan).not_to have_received(:refresh_from_stripe)
      end
    end

    describe 'product.updated' do
      let(:event) { build_stripe_event(type: 'product.updated', data_object: ots_product) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)

        price_list = instance_double(Stripe::ListObject)
        allow(price_list).to receive(:auto_paging_each).and_yield(recurring_price)
        allow(Stripe::Price).to receive(:list).with(product: 'prod_ots_123', active: true).and_return(price_list)

        allow(Billing::Plan).to receive(:extract_plan_data).and_return({ plan_id: 'test_plan' })
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
      end

      include_examples 'handles event successfully'

      it 'performs incremental sync for the product' do
        operation.call
        expect(Stripe::Product).to have_received(:retrieve).with('prod_ots_123')
        expect(Billing::Plan).to have_received(:upsert_from_stripe_data)
      end
    end

    describe 'non-OTS product is ignored' do
      let(:event) { build_stripe_event(type: 'product.updated', data_object: other_product) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Product).to receive(:retrieve).with('prod_other_456').and_return(other_product)
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
      end

      include_examples 'handles event successfully'

      it 'does not upsert non-OTS products' do
        operation.call
        expect(Billing::Plan).not_to have_received(:upsert_from_stripe_data)
      end
    end

    describe 'product from wrong region is skipped' do
      # Product is a valid OTS product but belongs to a different region (CA)
      # while the deployment is configured for NZ.
      let(:ca_product) do
        build_stripe_product(
          id: 'prod_ca_999',
          name: 'Identity Plus CA',
          metadata: { 'app' => 'onetimesecret', 'tier' => 'identity_plus', 'region' => 'CA' }
        )
      end
      let(:event) { build_stripe_event(type: 'product.updated', data_object: ca_product) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Product).to receive(:retrieve).with('prod_ca_999').and_return(ca_product)
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        # Configure the deployment to be isolated to NZ
        allow(Onetime.billing_config).to receive(:region).and_return('NZ')
      end

      include_examples 'handles event successfully'

      it 'does not upsert a product from a different region' do
        operation.call
        expect(Billing::Plan).not_to have_received(:upsert_from_stripe_data)
      end
    end
  end

  describe 'price events (incremental sync)' do
    describe 'price.created' do
      let(:event) { build_stripe_event(type: 'price.created', data_object: recurring_price) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Price).to receive(:retrieve).with('price_ots_monthly').and_return(recurring_price)
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)
        allow(Billing::Plan).to receive(:extract_plan_data).and_return({ plan_id: 'test_plan' })
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
      end

      include_examples 'handles event successfully'

      it 'fetches fresh price and product from Stripe' do
        operation.call
        expect(Stripe::Price).to have_received(:retrieve).with('price_ots_monthly')
        expect(Stripe::Product).to have_received(:retrieve).with('prod_ots_123')
      end

      it 'upserts the single plan' do
        operation.call
        expect(Billing::Plan).to have_received(:upsert_from_stripe_data)
      end
    end

    describe 'price.updated' do
      let(:event) { build_stripe_event(type: 'price.updated', data_object: recurring_price) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Price).to receive(:retrieve).with('price_ots_monthly').and_return(recurring_price)
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)
        allow(Billing::Plan).to receive(:extract_plan_data).and_return({ plan_id: 'test_plan' })
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
      end

      include_examples 'handles event successfully'
    end

    describe 'one-time price is skipped' do
      let(:event) { build_stripe_event(type: 'price.created', data_object: one_time_price) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Price).to receive(:retrieve).with('price_one_time').and_return(one_time_price)
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
      end

      include_examples 'handles event successfully'

      it 'does not upsert one-time prices' do
        operation.call
        expect(Billing::Plan).not_to have_received(:upsert_from_stripe_data)
      end
    end

    describe 'price for product from wrong region is skipped' do
      # Price belongs to a CA product; deployment is configured for NZ.
      let(:ca_product) do
        build_stripe_product(
          id: 'prod_ca_999',
          name: 'Identity Plus CA',
          metadata: { 'app' => 'onetimesecret', 'tier' => 'identity_plus', 'region' => 'CA' }
        )
      end
      let(:ca_price) do
        Stripe::Price.construct_from({
          id: 'price_ca_monthly',
          object: 'price',
          product: 'prod_ca_999',
          type: 'recurring',
          active: true,
          unit_amount: 1900,
          currency: 'cad',
          billing_scheme: 'per_unit',
          recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' },
        })
      end
      let(:event) { build_stripe_event(type: 'price.created', data_object: ca_price) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before do
        allow(Stripe::Price).to receive(:retrieve).with('price_ca_monthly').and_return(ca_price)
        allow(Stripe::Product).to receive(:retrieve).with('prod_ca_999').and_return(ca_product)
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
        # Configure the deployment to be isolated to NZ
        allow(Onetime.billing_config).to receive(:region).and_return('NZ')
      end

      include_examples 'handles event successfully'

      it 'does not upsert a price whose product belongs to a different region' do
        operation.call
        expect(Billing::Plan).not_to have_received(:upsert_from_stripe_data)
      end
    end
  end

  describe 'deletion events (soft-delete)' do
    describe 'product.deleted' do
      let(:deleted_product) do
        build_stripe_product(id: 'prod_deleted', name: 'Deleted Product')
      end
      let(:event) { build_stripe_event(type: 'product.deleted', data_object: deleted_product) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      let(:mock_plan) do
        instance_double(
          Billing::Plan,
          plan_id: 'deleted_plan',
          stripe_product_id: 'prod_deleted',
          'active=': nil,
          'last_synced_at=': nil,
          save: true
        )
      end

      before do
        allow(Billing::Plan).to receive(:list_plans).and_return([mock_plan])
        allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
      end

      include_examples 'handles event successfully'

      it 'marks matching plans as inactive' do
        operation.call
        expect(mock_plan).to have_received(:active=).with('false')
        expect(mock_plan).to have_received(:save)
      end

      it 'rebuilds the price ID cache' do
        operation.call
        expect(Billing::Plan).to have_received(:rebuild_stripe_price_id_cache)
      end
    end

    describe 'price.deleted' do
      let(:deleted_price) do
        Stripe::Price.construct_from({
          id: 'price_deleted',
          object: 'price',
          product: 'prod_test',
        })
      end
      let(:event) { build_stripe_event(type: 'price.deleted', data_object: deleted_price) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      context 'when plan exists for price' do
        let(:mock_plan) do
          instance_double(
            Billing::Plan,
            plan_id: 'deleted_plan',
            'active=': nil,
            'last_synced_at=': nil,
            save: true
          )
        end

        before do
          allow(Billing::Plan).to receive(:find_by_stripe_price_id)
            .with('price_deleted')
            .and_return(mock_plan)
          allow(Billing::Plan).to receive(:rebuild_stripe_price_id_cache)
        end

        include_examples 'handles event successfully'

        it 'marks the plan as inactive' do
          operation.call
          expect(mock_plan).to have_received(:active=).with('false')
          expect(mock_plan).to have_received(:save)
        end
      end

      context 'when no plan exists for price' do
        before do
          allow(Billing::Plan).to receive(:find_by_stripe_price_id)
            .with('price_deleted')
            .and_return(nil)
        end

        include_examples 'handles event successfully'

        it 'does not raise an error' do
          expect { operation.call }.not_to raise_error
        end
      end
    end
  end

  describe 'legacy plan events (full refresh)' do
    let(:plan_object) do
      Stripe::StripeObject.construct_from({
        id: 'plan_legacy',
        object: 'plan',
      })
    end

    describe 'plan.created' do
      let(:event) { build_stripe_event(type: 'plan.created', data_object: plan_object) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before { allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(true) }

      include_examples 'handles event successfully'

      it 'calls full refresh_from_stripe for legacy plan events' do
        operation.call
        expect(Billing::Plan).to have_received(:refresh_from_stripe)
      end
    end

    describe 'plan.updated' do
      let(:event) { build_stripe_event(type: 'plan.updated', data_object: plan_object) }
      let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

      before { allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(true) }

      include_examples 'handles event successfully'

      it 'calls full refresh_from_stripe for legacy plan events' do
        operation.call
        expect(Billing::Plan).to have_received(:refresh_from_stripe)
      end
    end
  end

  describe 'error handling' do
    let(:event) { build_stripe_event(type: 'product.updated', data_object: ots_product) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    context 'when Stripe API fails' do
      before do
        allow(Stripe::Product).to receive(:retrieve)
          .and_raise(Stripe::APIError.new('API unavailable'))
      end

      it 'returns :success (errors are non-fatal)' do
        expect(operation.call).to eq(:success)
      end

      it 'does not propagate the error' do
        expect { operation.call }.not_to raise_error
      end
    end

    context 'when upsert fails' do
      before do
        allow(Stripe::Product).to receive(:retrieve).with('prod_ots_123').and_return(ots_product)

        price_list = instance_double(Stripe::ListObject)
        allow(price_list).to receive(:auto_paging_each).and_yield(recurring_price)
        allow(Stripe::Price).to receive(:list).and_return(price_list)

        allow(Billing::Plan).to receive(:extract_plan_data).and_return({ plan_id: 'test' })
        allow(Billing::Plan).to receive(:upsert_from_stripe_data)
          .and_raise(StandardError, 'Redis connection failed')
      end

      it 'returns :success (errors are non-fatal)' do
        expect(operation.call).to eq(:success)
      end

      it 'does not propagate the error' do
        expect { operation.call }.not_to raise_error
      end
    end

    context 'when circuit breaker is open' do
      let(:webhook_event) do
        instance_double(
          Billing::StripeWebhookEvent,
          circuit_retry_exhausted?: false,
          circuit_retry_count: '0',
          schedule_circuit_retry: true
        )
      end

      let(:operation_with_context) do
        Billing::Operations::ProcessWebhookEvent.new(
          event: event,
          context: { webhook_event: webhook_event }
        )
      end

      before do
        allow(Billing::StripeCircuitBreaker).to receive(:call)
          .and_raise(Billing::CircuitOpenError.new('Circuit open', retry_after: 60))
      end

      it 'schedules circuit retry when webhook_event is available' do
        result = operation_with_context.call
        expect(result).to eq(:queued)
        expect(webhook_event).to have_received(:schedule_circuit_retry).with(delay_seconds: 60)
      end

      it 'returns :success when no webhook_event in context' do
        result = operation.call
        expect(result).to eq(:success)
      end
    end

    context 'when circuit retry is exhausted' do
      let(:webhook_event) do
        instance_double(
          Billing::StripeWebhookEvent,
          circuit_retry_exhausted?: true,
          circuit_retry_count: '5',
          mark_failed!: true
        )
      end

      let(:operation_with_context) do
        Billing::Operations::ProcessWebhookEvent.new(
          event: event,
          context: { webhook_event: webhook_event }
        )
      end

      before do
        allow(Billing::StripeCircuitBreaker).to receive(:call)
          .and_raise(Billing::CircuitOpenError.new('Circuit open', retry_after: 60))
      end

      it 'marks event as failed when max retries reached' do
        result = operation_with_context.call
        expect(result).to eq(:success)
        expect(webhook_event).to have_received(:mark_failed!)
      end
    end
  end
end
