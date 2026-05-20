# apps/web/billing/spec/operations/catalog/pull_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/pull'

RSpec.describe Billing::Operations::Catalog::Pull, :billing do
  describe '.call' do
    let(:progress_messages) { [] }
    let(:progress_proc) { ->(msg) { progress_messages << msg } }

    before do
      allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(5)
      allow(Billing::Plan).to receive(:upsert_config_only_plans).and_return(1)
      allow(Billing::Plan).to receive(:clear_cache)
    end

    context 'successful pull' do
      subject(:result) { described_class.call(progress: progress_proc) }

      it 'returns success result' do
        expect(result.success).to be true
      end

      it 'reports plans synced count' do
        expect(result.plans_synced).to eq(5)
      end

      it 'reports config plans loaded' do
        expect(result.config_plans_loaded).to eq(1)
      end

      it 'calls progress with status messages' do
        result
        expect(progress_messages).to include('Pulling from Stripe to Redis cache...')
      end
    end

    context 'with clear_cache option' do
      subject(:result) { described_class.call(clear_cache: true, progress: progress_proc) }

      it 'clears cache before pulling' do
        expect(Billing::Plan).to receive(:clear_cache).ordered
        expect(Billing::Plan).to receive(:refresh_from_stripe).ordered
        result
      end

      it 'sets cache_cleared flag' do
        expect(result.cache_cleared).to be true
      end

      it 'reports cache clearing in progress' do
        result
        expect(progress_messages).to include('Clearing existing plan cache...')
        expect(progress_messages).to include('Cache cleared')
      end
    end

    context 'without clear_cache option' do
      subject(:result) { described_class.call }

      it 'cache_cleared is false' do
        expect(result.cache_cleared).to be false
      end
    end

    context 'Stripe error' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(Stripe::APIError.new('API key invalid'))
      end

      subject(:result) { described_class.call }

      it 'returns failure result' do
        expect(result.success).to be false
      end

      it 'includes error message' do
        expect(result.errors).to include(match(/Stripe error/))
      end
    end

    context 'unexpected error' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(StandardError.new('Network timeout'))
      end

      subject(:result) { described_class.call }

      it 'returns failure result' do
        expect(result.success).to be false
      end

      it 'includes error class and message' do
        expect(result.errors.first).to include('StandardError')
        expect(result.errors.first).to include('Network timeout')
      end
    end
  end

  describe 'Result struct' do
    it 'has expected fields' do
      result = described_class::Result.new(success: true)
      expect(result).to respond_to(:success, :plans_synced, :plans_pruned,
                                   :config_plans_loaded, :cache_cleared, :errors)
    end

    it 'has sensible defaults' do
      result = described_class::Result.new(success: true)
      expect(result.plans_synced).to eq(0)
      expect(result.errors).to eq([])
    end
  end
end
