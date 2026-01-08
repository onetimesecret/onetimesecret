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

    context 'when cache is valid' do
      before do
        allow(initializer).to receive(:catalog_valid?).and_return(true)
      end

      it 'skips Stripe sync' do
        expect(Billing::Plan).not_to receive(:refresh_from_stripe)
        initializer.execute(nil)
      end

      it 'logs cache valid message' do
        expect(logger).to receive(:info).with('Cache valid, skipping Stripe sync')
        initializer.execute(nil)
      end
    end

    context 'when Stripe sync succeeds' do
      before do
        allow(initializer).to receive(:catalog_valid?).and_return(false)
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
        allow(initializer).to receive(:catalog_valid?).and_return(false)
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
        allow(initializer).to receive(:catalog_valid?).and_return(false)
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

  describe '#catalog_valid?' do
    let(:logger) { instance_double(SemanticLogger::Logger) }
    let(:instances_set) { double('instances') }

    before do
      allow(Onetime).to receive(:billing_logger).and_return(logger)
    end

    context 'when instances is empty' do
      before do
        allow(Billing::Plan).to receive(:instances).and_return(instances_set)
        allow(instances_set).to receive(:empty?).and_return(true)
      end

      it 'returns false' do
        expect(initializer.send(:catalog_valid?)).to be false
      end
    end

    context 'when instances is populated but no sync timestamp exists' do
      before do
        allow(Billing::Plan).to receive(:instances).and_return(instances_set)
        allow(instances_set).to receive(:empty?).and_return(false)
        allow(Billing::Plan).to receive(:catalog_last_synced_at).and_return(nil)
      end

      it 'returns false' do
        expect(initializer.send(:catalog_valid?)).to be false
      end
    end

    context 'when cache is stale (older than 12 hours)' do
      let(:stale_timestamp) { Time.now.to_i - (13 * 60 * 60) }

      before do
        allow(Billing::Plan).to receive(:instances).and_return(instances_set)
        allow(instances_set).to receive(:empty?).and_return(false)
        allow(Billing::Plan).to receive(:catalog_last_synced_at).and_return(stale_timestamp)
      end

      it 'returns false' do
        expect(initializer.send(:catalog_valid?)).to be false
      end
    end

    context 'when cache is fresh (within 12 hours)' do
      let(:fresh_timestamp) { Time.now.to_i - (6 * 60 * 60) }

      before do
        allow(Billing::Plan).to receive(:instances).and_return(instances_set)
        allow(instances_set).to receive(:empty?).and_return(false)
        allow(Billing::Plan).to receive(:catalog_last_synced_at).and_return(fresh_timestamp)
      end

      it 'returns true' do
        expect(initializer.send(:catalog_valid?)).to be true
      end
    end
  end
end
