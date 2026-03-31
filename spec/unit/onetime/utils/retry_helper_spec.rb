# spec/unit/onetime/utils/retry_helper_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/utils/retry_helper'

RSpec.describe Onetime::Utils::RetryHelper do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include Onetime::Utils::RetryHelper
    end
  end

  let(:instance) { test_class.new }
  # Use a mock that accepts structured logging (message + keyword args)
  # like SemanticLogger. Standard Logger only accepts 0-1 args.
  let(:mock_logger) do
    logger = Object.new
    def logger.info(message = nil, **payload); end
    def logger.error(message = nil, **payload); end
    logger
  end

  describe '.compute_delay' do
    it 'computes exponential backoff for retry 1' do
      # base_delay * 2^0 = 1.0, plus up to 30% jitter
      allow(described_class).to receive(:rand).and_return(0.5)
      delay = described_class.compute_delay(1.0, 1)
      # 1.0 + (0.5 * 1.0 * 0.3) = 1.15
      expect(delay).to be_within(0.01).of(1.15)
    end

    it 'computes exponential backoff for retry 2' do
      # base_delay * 2^1 = 2.0, plus up to 30% jitter
      allow(described_class).to receive(:rand).and_return(0.5)
      delay = described_class.compute_delay(1.0, 2)
      # 2.0 + (0.5 * 2.0 * 0.3) = 2.3
      expect(delay).to be_within(0.01).of(2.3)
    end

    it 'computes exponential backoff for retry 3' do
      # base_delay * 2^2 = 4.0, plus up to 30% jitter
      allow(described_class).to receive(:rand).and_return(0.5)
      delay = described_class.compute_delay(1.0, 3)
      # 4.0 + (0.5 * 4.0 * 0.3) = 4.6
      expect(delay).to be_within(0.01).of(4.6)
    end

    it 'respects custom base_delay' do
      allow(described_class).to receive(:rand).and_return(0)
      delay = described_class.compute_delay(0.5, 1)
      expect(delay).to eq(0.5)
    end
  end

  describe '.with_retry (module method)' do
    it 'returns block result on success' do
      result = described_class.with_retry { 'success' }
      expect(result).to eq('success')
    end

    it 'does not retry when block succeeds' do
      call_count = 0
      described_class.with_retry do
        call_count += 1
        'success'
      end
      expect(call_count).to eq(1)
    end

    context 'with transient failures' do
      it 'retries on StandardError' do
        call_count = 0
        allow(described_class).to receive(:sleep)

        result = described_class.with_retry(max_retries: 3, logger: mock_logger) do
          call_count += 1
          raise StandardError, 'transient' if call_count < 3

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(call_count).to eq(3)
      end

      it 'sleeps between retries with backoff' do
        call_count = 0
        delays = []

        # Stub sleep on the instance receiving with_retry, not on the module
        allow_any_instance_of(Object).to receive(:sleep) { |_obj, d| delays << d }
        allow(described_class).to receive(:rand).and_return(0)

        begin
          described_class.with_retry(max_retries: 2, base_delay: 1.0, logger: mock_logger) do
            call_count += 1
            raise StandardError, 'always fails'
          end
        rescue StandardError
          # expected
        end

        expect(delays.length).to eq(2)
        expect(delays[0]).to eq(1.0) # 1.0 * 2^0
        expect(delays[1]).to eq(2.0) # 1.0 * 2^1
      end

      it 'logs retry attempts' do
        allow_any_instance_of(Object).to receive(:sleep)

        # Structured logging: message + keyword args
        expect(mock_logger).to receive(:info).with('Retry attempt', hash_including(attempt: 1, max: 2))
        expect(mock_logger).to receive(:info).with('Retry attempt', hash_including(attempt: 2, max: 2))
        expect(mock_logger).to receive(:error).with('Max retries exceeded', hash_including(max: 2))

        expect do
          described_class.with_retry(max_retries: 2, logger: mock_logger) do
            raise StandardError, 'transient'
          end
        end.to raise_error(StandardError, 'transient')
      end
    end

    context 'with max retries exceeded' do
      it 're-raises the exception' do
        allow_any_instance_of(Object).to receive(:sleep)

        expect do
          described_class.with_retry(max_retries: 2, logger: mock_logger) do
            raise StandardError, 'persistent failure'
          end
        end.to raise_error(StandardError, 'persistent failure')
      end

      it 'attempts max_retries times' do
        call_count = 0
        allow_any_instance_of(Object).to receive(:sleep)

        expect do
          described_class.with_retry(max_retries: 3, logger: mock_logger) do
            call_count += 1
            raise StandardError, 'always fails'
          end
        end.to raise_error(StandardError)

        # 1 initial + 3 retries = 4 total attempts
        expect(call_count).to eq(4)
      end
    end

    context 'with retriable predicate' do
      let(:retriable) { ->(ex) { ex.message.include?('retry-me') } }

      it 'retries when predicate returns true' do
        call_count = 0
        allow_any_instance_of(Object).to receive(:sleep)

        result = described_class.with_retry(max_retries: 3, retriable: retriable, logger: mock_logger) do
          call_count += 1
          raise StandardError, 'retry-me' if call_count < 2

          'recovered'
        end

        expect(result).to eq('recovered')
        expect(call_count).to eq(2)
      end

      it 'does not retry when predicate returns false' do
        call_count = 0

        expect do
          described_class.with_retry(max_retries: 3, retriable: retriable, logger: mock_logger) do
            call_count += 1
            raise StandardError, 'do-not-retry'
          end
        end.to raise_error(StandardError, 'do-not-retry')

        expect(call_count).to eq(1)
      end

      it 'logs non-retriable errors' do
        expect(mock_logger).to receive(:error).with(
          'Non-retriable error, skipping retries',
          hash_including(error_class: 'StandardError', error_message: 'do-not-retry'),
        )

        expect do
          described_class.with_retry(max_retries: 3, retriable: retriable, logger: mock_logger) do
            raise StandardError, 'do-not-retry'
          end
        end.to raise_error(StandardError)
      end
    end

    context 'with context parameter' do
      it 'includes context in log messages' do
        allow_any_instance_of(Object).to receive(:sleep)

        # Structured logging: context is passed as keyword arg, not in message string
        expect(mock_logger).to receive(:info).with('Retry attempt', hash_including(context: 'DNS lookup', attempt: 1))
        expect(mock_logger).to receive(:error).with('Max retries exceeded', hash_including(context: 'DNS lookup'))

        expect do
          described_class.with_retry(max_retries: 1, context: 'DNS lookup', logger: mock_logger) do
            raise StandardError, 'timeout'
          end
        end.to raise_error(StandardError)
      end
    end
  end

  describe '#with_retry (instance method)' do
    it 'works when included in a class' do
      result = instance.with_retry { 'success' }
      expect(result).to eq('success')
    end

    it 'retries on failure' do
      call_count = 0
      allow(described_class).to receive(:sleep)

      result = instance.with_retry(max_retries: 2) do
        call_count += 1
        raise StandardError, 'fail' if call_count < 2

        'recovered'
      end

      expect(result).to eq('recovered')
    end
  end

  describe 'jitter randomization' do
    it 'adds up to 30% jitter to delay' do
      # With rand returning 1.0, jitter = 1.0 * delay * 0.3 = 0.3 * delay
      allow(described_class).to receive(:rand).and_return(1.0)
      delay = described_class.compute_delay(1.0, 1)
      expect(delay).to eq(1.3) # 1.0 + 0.3

      # With rand returning 0.0, no jitter
      allow(described_class).to receive(:rand).and_return(0.0)
      delay = described_class.compute_delay(1.0, 1)
      expect(delay).to eq(1.0)
    end
  end
end
