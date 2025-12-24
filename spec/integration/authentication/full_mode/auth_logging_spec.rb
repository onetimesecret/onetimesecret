# spec/integration/authentication/full_mode/auth_logging_spec.rb
#
# frozen_string_literal: true

# Tests for Auth::Logging module - provides structured logging for authentication events.
# This spec does not require database access - it tests the logging API surface.

require 'spec_helper'

RSpec.describe 'Auth::Logging', :full_auth_mode, type: :integration do
  before(:all) do
    require_relative '../../../../apps/web/auth/config'
  end

  # Helper to reference the module
  let(:logging_module) { Auth::Logging }

  describe '.generate_correlation_id' do
    it 'responds to generate_correlation_id' do
      expect(logging_module).to respond_to(:generate_correlation_id)
    end

    it 'returns a 12-character string' do
      expect(logging_module.generate_correlation_id.length).to eq(12)
    end

    it 'returns unique values' do
      ids = 10.times.map { logging_module.generate_correlation_id }
      expect(ids.uniq.length).to eq(10)
    end
  end

  describe '.log_auth_event' do
    it 'accepts standard auth event parameters' do
      expect {
        logging_module.log_auth_event(
          :test_event,
          level: :info,
          email: 'test@example.com',
          correlation_id: 'abc123def456'
        )
      }.not_to raise_error
    end

    it 'accepts correlation_id and account_id' do
      expect {
        logging_module.log_auth_event(
          :test_event,
          level: :info,
          correlation_id: 'test_corr_id_123',
          account_id: 42
        )
      }.not_to raise_error
    end

    it 'handles missing correlation_id gracefully' do
      expect {
        logging_module.log_auth_event(
          :test_event_no_corr,
          level: :info,
          account_id: 42
        )
      }.not_to raise_error
    end

    it 'handles nil email gracefully' do
      expect {
        logging_module.log_auth_event(
          :test_event,
          level: :info,
          email: nil,
          correlation_id: 'nil_email_test'
        )
      }.not_to raise_error
    end
  end

  describe '.log_metric' do
    it 'accepts metric data with value and unit' do
      expect {
        logging_module.log_metric(
          :session_sync_duration,
          value: 45.67,
          unit: :ms,
          account_id: 123,
          correlation_id: 'metric_test_id'
        )
      }.not_to raise_error
    end
  end

  describe '.measure' do
    it 'returns the block result' do
      result = logging_module.measure(:test_operation, account_id: 99) do
        'operation_result'
      end
      expect(result).to eq('operation_result')
    end

    it 'executes the block and logs duration' do
      executed = false
      logging_module.measure(:test_operation, account_id: 99) do
        executed = true
      end
      expect(executed).to be true
    end
  end

  describe '.log_error' do
    it 'handles exceptions properly' do
      exception = StandardError.new('Test error')

      expect {
        logging_module.log_error(
          :test_error_event,
          exception: exception,
          account_id: 42,
          correlation_id: 'error_test_id'
        )
      }.not_to raise_error
    end
  end

  describe '.log_operation' do
    it 'provides structured operation logging' do
      expect {
        logging_module.log_operation(
          :session_sync_start,
          level: :info,
          account_id: 123,
          correlation_id: 'op_test_123'
        )
      }.not_to raise_error
    end
  end

  describe 'correlation_id linking' do
    it 'supports multiple events with same correlation_id' do
      correlation_id = logging_module.generate_correlation_id

      expect {
        logging_module.log_auth_event(:login_attempt, correlation_id: correlation_id)
        logging_module.log_auth_event(:login_success, correlation_id: correlation_id)
        logging_module.log_operation(:session_sync_start, correlation_id: correlation_id)
        logging_module.log_operation(:session_sync_complete, correlation_id: correlation_id)
      }.not_to raise_error
    end
  end
end
