# apps/web/billing/spec/operations/catalog/stripe_retry_spec.rb
#
# frozen_string_literal: true

require_relative '../../support/billing_spec_helper'
require_relative '../../../operations/catalog/stripe_retry'

RSpec.describe Billing::Operations::Catalog::StripeRetry, :billing do
  describe '.with_retry' do
    let(:call_count) { [] }

    before do
      # Reset call tracking
      call_count.clear
    end

    context 'successful call' do
      it 'returns block result without retrying' do
        result = described_class.with_retry { 'success' }
        expect(result).to eq('success')
      end

      it 'executes block exactly once' do
        described_class.with_retry { call_count << 1 }
        expect(call_count.size).to eq(1)
      end
    end

    context 'APIConnectionError with linear backoff' do
      it 'retries up to max_retries times' do
        attempts = 0
        expect do
          described_class.with_retry(max_retries: 3) do
            attempts += 1
            raise Stripe::APIConnectionError.new('Connection failed')
          end
        end.to raise_error(Stripe::APIConnectionError)
        expect(attempts).to eq(4) # initial + 3 retries
      end

      it 'succeeds after transient failure' do
        attempts = 0
        result = described_class.with_retry do
          attempts += 1
          raise Stripe::APIConnectionError.new('Transient') if attempts < 2

          'recovered'
        end
        expect(result).to eq('recovered')
        expect(attempts).to eq(2)
      end

      it 'uses linear backoff (delay = BASE_DELAY * retry_number)' do
        delays = []
        allow(described_class).to receive(:sleep) { |d| delays << d }

        expect do
          described_class.with_retry(max_retries: 3) do
            raise Stripe::APIConnectionError.new('Connection failed')
          end
        end.to raise_error(Stripe::APIConnectionError)

        # Linear: 2*1, 2*2, 2*3
        expect(delays).to eq([2, 4, 6])
      end

      it 'respects custom max_retries' do
        attempts = 0
        expect do
          described_class.with_retry(max_retries: 1) do
            attempts += 1
            raise Stripe::APIConnectionError.new('Failed')
          end
        end.to raise_error(Stripe::APIConnectionError)
        expect(attempts).to eq(2) # initial + 1 retry
      end
    end

    context 'RateLimitError with exponential backoff' do
      it 'retries up to max_retries times' do
        attempts = 0
        expect do
          described_class.with_retry(max_retries: 3) do
            attempts += 1
            raise Stripe::RateLimitError.new('Rate limited')
          end
        end.to raise_error(Stripe::RateLimitError)
        expect(attempts).to eq(4) # initial + 3 retries
      end

      it 'succeeds after rate limit clears' do
        attempts = 0
        result = described_class.with_retry do
          attempts += 1
          raise Stripe::RateLimitError.new('Rate limited') if attempts < 3

          'success'
        end
        expect(result).to eq('success')
        expect(attempts).to eq(3)
      end

      it 'uses exponential backoff (delay = BASE_DELAY * 2^retry_number)' do
        delays = []
        allow(described_class).to receive(:sleep) { |d| delays << d }

        expect do
          described_class.with_retry(max_retries: 3) do
            raise Stripe::RateLimitError.new('Rate limited')
          end
        end.to raise_error(Stripe::RateLimitError)

        # Exponential: 2*2^1, 2*2^2, 2*2^3
        expect(delays).to eq([4, 8, 16])
      end
    end

    context 'other Stripe errors' do
      it 'does not retry on APIError' do
        attempts = 0
        expect do
          described_class.with_retry do
            attempts += 1
            raise Stripe::APIError.new('Bad request')
          end
        end.to raise_error(Stripe::APIError)
        expect(attempts).to eq(1) # no retry
      end

      it 'does not retry on AuthenticationError' do
        attempts = 0
        expect do
          described_class.with_retry do
            attempts += 1
            raise Stripe::AuthenticationError.new('Invalid key')
          end
        end.to raise_error(Stripe::AuthenticationError)
        expect(attempts).to eq(1)
      end

      it 'does not retry on InvalidRequestError' do
        attempts = 0
        expect do
          described_class.with_retry do
            attempts += 1
            raise Stripe::InvalidRequestError.new('Bad param', 'param')
          end
        end.to raise_error(Stripe::InvalidRequestError)
        expect(attempts).to eq(1)
      end
    end

    context 'non-Stripe errors' do
      it 'does not retry on StandardError' do
        attempts = 0
        expect do
          described_class.with_retry do
            attempts += 1
            raise StandardError.new('Generic error')
          end
        end.to raise_error(StandardError)
        expect(attempts).to eq(1)
      end
    end

    context 'constants' do
      it 'has MAX_RETRIES of 3' do
        expect(described_class::MAX_RETRIES).to eq(3)
      end

      it 'has BASE_DELAY of 2 seconds' do
        expect(described_class::BASE_DELAY).to eq(2)
      end
    end
  end
end
