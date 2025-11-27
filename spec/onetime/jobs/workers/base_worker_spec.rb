# spec/onetime/jobs/workers/base_worker_spec.rb
#
# frozen_string_literal: true

require_relative '../../../spec_helper'
require_relative '../../../../lib/onetime/jobs/workers/base_worker'

RSpec.describe Onetime::Jobs::Workers::BaseWorker do
  # Create a test worker class that includes the module
  let(:test_worker_class) do
    Class.new do
      include Onetime::Jobs::Workers::BaseWorker

      def self.name
        'TestWorker'
      end

      def self.queue_name
        'test.queue'
      end

      def perform(msg)
        msg['processed'] = true
        msg
      end
    end
  end

  describe 'module inclusion' do
    it 'can be included in a class' do
      expect(test_worker_class.included_modules).to include(described_class)
    end
  end

  describe 'class methods' do
    it 'requires queue_name to be defined' do
      incomplete_class = Class.new do
        include Onetime::Jobs::Workers::BaseWorker
      end

      expect { incomplete_class.queue_name }
        .to raise_error(NotImplementedError, /must define queue_name/)
    end

    it 'provides default worker_threads' do
      expect(test_worker_class.worker_threads).to be_a(Integer)
      expect(test_worker_class.worker_threads).to be > 0
    end

    it 'provides default prefetch_count' do
      expect(test_worker_class.prefetch_count).to eq(10)
    end
  end

  describe 'instance methods' do
    subject(:worker) { test_worker_class.new }

    describe '#parse_message' do
      it 'parses valid JSON' do
        json = '{"template": "welcome", "data": {"email": "test@example.com"}}'
        result = worker.send(:parse_message, json)

        expect(result).to eq({
          'template' => 'welcome',
          'data' => { 'email' => 'test@example.com' }
        })
      end

      it 'raises JSON::ParserError for invalid JSON' do
        expect { worker.send(:parse_message, 'not json') }
          .to raise_error(JSON::ParserError)
      end
    end

    describe '#retriable?' do
      it 'returns true for Timeout::Error' do
        error = Timeout::Error.new
        expect(worker.send(:retriable?, error)).to be true
      end

      it 'returns true for Errno::ECONNREFUSED' do
        error = Errno::ECONNREFUSED.new
        expect(worker.send(:retriable?, error)).to be true
      end

      it 'returns false for generic StandardError' do
        error = StandardError.new('generic error')
        expect(worker.send(:retriable?, error)).to be false
      end
    end

    describe '#worker_name' do
      it 'returns the class name' do
        expect(worker.send(:worker_name)).to eq('TestWorker')
      end
    end
  end
end
