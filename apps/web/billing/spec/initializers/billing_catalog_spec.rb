# apps/web/billing/spec/initializers/billing_catalog_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../initializers/billing_catalog'

RSpec.describe Billing::Initializers::BillingCatalog do
  let(:initializer) { described_class.new }

  describe '#should_skip?' do
    context 'when billing is disabled' do
      before do
        allow(Onetime).to receive(:billing_config).and_return(
          double(enabled?: false)
        )
      end

      it 'returns true' do
        expect(initializer.should_skip?).to be true
      end
    end

    context 'when in test environment' do
      before do
        allow(Onetime).to receive(:billing_config).and_return(
          double(enabled?: true)
        )
        allow(ENV).to receive(:[]).with('RACK_ENV').and_return('test')
      end

      it 'returns true' do
        expect(initializer.should_skip?).to be true
      end
    end

    context 'when billing is enabled and not in test' do
      before do
        allow(Onetime).to receive(:billing_config).and_return(
          double(enabled?: true)
        )
        allow(ENV).to receive(:[]).with('RACK_ENV').and_return('production')
      end

      it 'returns false' do
        expect(initializer.should_skip?).to be false
      end
    end
  end

  describe '#execute' do
    let(:logger) { instance_double(SemanticLogger::Logger) }

    before do
      allow(Onetime).to receive(:billing_logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
      allow(logger).to receive(:error)
    end

    context 'when Stripe sync succeeds' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
      end

      it 'refreshes plans from Stripe' do
        expect(Billing::Plan).to receive(:refresh_from_stripe)
        initializer.execute(nil)
      end

      it 'logs success' do
        expect(logger).to receive(:info).with('Refreshing plan cache from Stripe')
        expect(logger).to receive(:info).with('Plan cache refreshed successfully')
        initializer.execute(nil)
      end
    end

    context 'when Stripe sync fails' do
      let(:stripe_error) { Stripe::APIConnectionError.new('Network error') }

      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(stripe_error)
        allow(Billing::Plan).to receive(:load_all_from_config).and_return(5)
      end

      it 'falls back to loading from config' do
        expect(Billing::Plan).to receive(:load_all_from_config)
        initializer.execute(nil)
      end

      it 'logs the fallback' do
        expect(logger).to receive(:warn).with(
          'Stripe sync failed, falling back to billing.yaml',
          hash_including(exception: an_instance_of(Stripe::APIConnectionError))
        )
        expect(logger).to receive(:info).with('Loaded 5 plans from billing.yaml fallback')
        initializer.execute(nil)
      end
    end

    context 'when both Stripe and config fallback fail' do
      let(:stripe_error) { Stripe::APIConnectionError.new('Network error') }
      let(:config_error) { StandardError.new('Config file missing') }

      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe).and_raise(stripe_error)
        allow(Billing::Plan).to receive(:load_all_from_config).and_raise(config_error)
      end

      it 'raises the config error' do
        expect { initializer.execute(nil) }.to raise_error(StandardError, 'Config file missing')
      end

      it 'logs both failures' do
        expect(logger).to receive(:warn).with(
          'Stripe sync failed, falling back to billing.yaml',
          anything
        )
        expect(logger).to receive(:error).with(
          'Fallback to billing.yaml also failed',
          hash_including(message: 'Config file missing')
        )

        expect { initializer.execute(nil) }.to raise_error(StandardError)
      end
    end
  end
end
