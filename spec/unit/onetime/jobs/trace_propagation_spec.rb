# spec/unit/onetime/jobs/trace_propagation_spec.rb
#
# frozen_string_literal: true

# Purpose:
#   Tests for the TracePropagation module that enables Sentry distributed tracing
#   across RabbitMQ message boundaries. This module provides utilities for:
#   - Extracting trace headers from the current Sentry transaction (publisher side)
#   - Parsing trace headers from incoming messages (worker side)
#   - Properly continuing traces in background workers
#
# The TracePropagation module is designed to work with Sentry's continue_trace API
# to link asynchronous job execution back to the originating HTTP request.
#
# Test Categories:
#   - extract_trace_headers: Publisher-side header generation
#   - parse_trace_headers: Worker-side header extraction from message metadata
#   - continue_trace: Worker-side trace continuation with transaction wrapping
#
# Setup Requirements:
#   - Sentry mocking (no real DSN needed)
#   - AMQP metadata stubs for worker tests
#

require 'spec_helper'
require 'support/amqp_stubs'
require 'onetime/jobs/trace_propagation'

RSpec.describe Onetime::Jobs::TracePropagation do
  # Define a minimal Sentry stub for tests that need it.
  # Some tests use hide_const('Sentry') to simulate Sentry being unavailable.
  before do
    unless defined?(Sentry)
      stub_const('Sentry', Module.new do
        def self.initialized?
          false
        end

        def self.get_current_scope
          nil
        end

        def self.get_trace_propagation_headers
          nil
        end

        def self.continue_trace(headers, name:, op:)
          nil
        end

        def self.with_scope
          yield nil if block_given?
        end
      end)
    end
  end

  describe '.extract_trace_headers' do
    context 'when Sentry is initialized with an active span' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(true)
      end

      it 'returns trace headers from Sentry' do
        mock_scope = instance_double('Sentry::Scope')
        mock_span = instance_double('Sentry::Span')
        expected_headers = {
          'sentry-trace' => '00-abcd1234-5678ef90-01',
          'baggage' => 'sentry-environment=production,sentry-release=1.0.0'
        }

        allow(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        allow(mock_scope).to receive(:get_span).and_return(mock_span)
        allow(Sentry).to receive(:get_trace_propagation_headers).and_return(expected_headers)

        headers = described_class.extract_trace_headers

        expect(headers).to eq(expected_headers)
      end

      it 'returns empty hash when get_trace_propagation_headers returns nil' do
        mock_scope = instance_double('Sentry::Scope')
        mock_span = instance_double('Sentry::Span')

        allow(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        allow(mock_scope).to receive(:get_span).and_return(mock_span)
        allow(Sentry).to receive(:get_trace_propagation_headers).and_return(nil)

        headers = described_class.extract_trace_headers

        expect(headers).to eq({})
      end

      it 'returns empty hash when no active span' do
        mock_scope = instance_double('Sentry::Scope')

        allow(Sentry).to receive(:get_current_scope).and_return(mock_scope)
        allow(mock_scope).to receive(:get_span).and_return(nil)

        headers = described_class.extract_trace_headers

        expect(headers).to eq({})
      end

      it 'returns empty hash when scope is nil' do
        allow(Sentry).to receive(:get_current_scope).and_return(nil)

        headers = described_class.extract_trace_headers

        expect(headers).to eq({})
      end
    end

    context 'when Sentry is not initialized' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it 'returns empty hash' do
        headers = described_class.extract_trace_headers

        expect(headers).to eq({})
      end

      it 'does not call any Sentry scope methods' do
        expect(Sentry).not_to receive(:get_current_scope)
        expect(Sentry).not_to receive(:get_trace_propagation_headers)

        described_class.extract_trace_headers
      end
    end

    context 'when Sentry is not defined' do
      before do
        hide_const('Sentry')
      end

      it 'returns empty hash without raising' do
        headers = described_class.extract_trace_headers

        expect(headers).to eq({})
      end
    end

    context 'when an error occurs during extraction' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(true)
        allow(Sentry).to receive(:get_current_scope).and_raise(StandardError.new('Sentry internal error'))
      end

      it 'returns empty hash and does not propagate the error' do
        expect {
          headers = described_class.extract_trace_headers
          expect(headers).to eq({})
        }.not_to raise_error
      end
    end
  end

  describe '.parse_trace_headers' do
    let(:metadata_with_trace) do
      MetadataStub.new(
        message_id: 'msg-123',
        headers: {
          'x-schema-version' => 1,
          'sentry-trace' => '00-abcd1234-5678ef90-01',
          'baggage' => 'sentry-environment=production'
        }
      )
    end

    let(:metadata_without_trace) do
      MetadataStub.new(
        message_id: 'msg-456',
        headers: {
          'x-schema-version' => 1
        }
      )
    end

    let(:metadata_with_nil_headers) do
      MetadataStub.new(
        message_id: 'msg-789',
        headers: nil
      )
    end

    context 'when metadata contains trace headers' do
      it 'extracts sentry-trace header' do
        result = described_class.parse_trace_headers(metadata_with_trace)

        expect(result['sentry-trace']).to eq('00-abcd1234-5678ef90-01')
      end

      it 'extracts baggage header' do
        result = described_class.parse_trace_headers(metadata_with_trace)

        expect(result['baggage']).to eq('sentry-environment=production')
      end

      it 'returns hash with both headers' do
        result = described_class.parse_trace_headers(metadata_with_trace)

        expect(result).to eq({
          'sentry-trace' => '00-abcd1234-5678ef90-01',
          'baggage' => 'sentry-environment=production'
        })
      end
    end

    context 'when metadata lacks trace headers' do
      it 'returns empty hash' do
        result = described_class.parse_trace_headers(metadata_without_trace)

        expect(result).to eq({})
      end
    end

    context 'when metadata headers are nil' do
      it 'returns empty hash' do
        result = described_class.parse_trace_headers(metadata_with_nil_headers)

        expect(result).to eq({})
      end
    end

    context 'when metadata is nil' do
      it 'returns empty hash' do
        result = described_class.parse_trace_headers(nil)

        expect(result).to eq({})
      end
    end

    context 'when only sentry-trace is present (no baggage)' do
      let(:metadata_trace_only) do
        MetadataStub.new(
          message_id: 'msg-abc',
          headers: {
            'sentry-trace' => '00-trace123-span456-01'
          }
        )
      end

      it 'returns hash with only sentry-trace' do
        result = described_class.parse_trace_headers(metadata_trace_only)

        expect(result).to eq({ 'sentry-trace' => '00-trace123-span456-01' })
      end
    end

    context 'when only baggage is present (edge case)' do
      let(:metadata_baggage_only) do
        MetadataStub.new(
          message_id: 'msg-xyz',
          headers: {
            'baggage' => 'sentry-environment=staging'
          }
        )
      end

      it 'returns hash with only baggage' do
        result = described_class.parse_trace_headers(metadata_baggage_only)

        expect(result).to eq({ 'baggage' => 'sentry-environment=staging' })
      end
    end

    context 'when headers is not a Hash' do
      let(:metadata_invalid_headers) do
        MetadataStub.new(
          message_id: 'msg-invalid',
          headers: 'not-a-hash'
        )
      end

      it 'returns empty hash' do
        result = described_class.parse_trace_headers(metadata_invalid_headers)

        expect(result).to eq({})
      end
    end
  end

  describe '.continue_trace' do
    let(:trace_headers) do
      {
        'sentry-trace' => '00-abcd1234-5678ef90-01',
        'baggage' => 'sentry-environment=production'
      }
    end

    context 'when Sentry is initialized' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(true)
      end

      context 'when continue_trace returns a transaction' do
        let(:mock_transaction) { instance_double('Sentry::Transaction') }
        let(:mock_scope) { instance_double('Sentry::Scope') }

        before do
          allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
          allow(Sentry).to receive(:continue_trace).and_return(mock_transaction)
          allow(mock_scope).to receive(:set_span)
          allow(mock_transaction).to receive(:set_status)
          allow(mock_transaction).to receive(:finish)
        end

        it 'calls Sentry.continue_trace with headers, name, and op' do
          expect(Sentry).to receive(:continue_trace).with(
            trace_headers,
            name: 'email.worker.process',
            op: 'queue.process'
          ).and_return(mock_transaction)

          described_class.continue_trace(trace_headers, name: 'email.worker.process') {}
        end

        it 'sets the transaction as the current span' do
          expect(mock_scope).to receive(:set_span).with(mock_transaction)

          described_class.continue_trace(trace_headers, name: 'test.operation') {}
        end

        it 'yields to the block' do
          block_called = false
          described_class.continue_trace(trace_headers, name: 'test') do
            block_called = true
          end

          expect(block_called).to be true
        end

        it 'returns the result of the block' do
          result = described_class.continue_trace(trace_headers, name: 'test') do
            'block result'
          end

          expect(result).to eq('block result')
        end

        it 'sets transaction status to ok on success' do
          expect(mock_transaction).to receive(:set_status).with('ok')

          described_class.continue_trace(trace_headers, name: 'test') {}
        end

        it 'finishes the transaction' do
          expect(mock_transaction).to receive(:finish)

          described_class.continue_trace(trace_headers, name: 'test') {}
        end

        it 'accepts custom op parameter' do
          expect(Sentry).to receive(:continue_trace).with(
            trace_headers,
            name: 'custom.operation',
            op: 'custom.op'
          ).and_return(mock_transaction)

          described_class.continue_trace(trace_headers, name: 'custom.operation', op: 'custom.op') {}
        end

        context 'when block raises an error' do
          it 'sets transaction status to internal_error' do
            expect(mock_transaction).to receive(:set_status).with('internal_error')

            expect {
              described_class.continue_trace(trace_headers, name: 'test') do
                raise StandardError, 'Processing failed'
              end
            }.to raise_error(StandardError, 'Processing failed')
          end

          it 'finishes the transaction before re-raising' do
            expect(mock_transaction).to receive(:finish)

            expect {
              described_class.continue_trace(trace_headers, name: 'test') do
                raise StandardError, 'Processing failed'
              end
            }.to raise_error(StandardError)
          end

          it 're-raises the original error' do
            expect {
              described_class.continue_trace(trace_headers, name: 'test') do
                raise StandardError, 'Original error'
              end
            }.to raise_error(StandardError, 'Original error')
          end
        end
      end

      context 'when continue_trace returns nil (no trace context)' do
        let(:mock_scope) { instance_double('Sentry::Scope') }

        before do
          allow(Sentry).to receive(:with_scope).and_yield(mock_scope)
          allow(Sentry).to receive(:continue_trace).and_return(nil)
        end

        it 'still yields to the block' do
          block_called = false
          described_class.continue_trace(trace_headers, name: 'test') do
            block_called = true
          end

          expect(block_called).to be true
        end

        it 'returns the result of the block' do
          result = described_class.continue_trace(trace_headers, name: 'test') do
            'result without transaction'
          end

          expect(result).to eq('result without transaction')
        end
      end
    end

    context 'when Sentry is not initialized' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it 'does not call Sentry.continue_trace' do
        expect(Sentry).not_to receive(:continue_trace)

        described_class.continue_trace(trace_headers, name: 'test') {}
      end

      it 'still yields to the block' do
        block_called = false
        described_class.continue_trace(trace_headers, name: 'test') do
          block_called = true
        end

        expect(block_called).to be true
      end

      it 'returns the result of the block' do
        result = described_class.continue_trace(trace_headers, name: 'test') do
          'fallback result'
        end

        expect(result).to eq('fallback result')
      end
    end

    context 'when no block is given' do
      before do
        allow(Sentry).to receive(:initialized?).and_return(false)
      end

      it 'returns nil' do
        result = described_class.continue_trace(trace_headers, name: 'test')

        expect(result).to be_nil
      end
    end

    context 'when Sentry is not defined' do
      before do
        hide_const('Sentry')
      end

      it 'yields to the block without error' do
        block_called = false
        described_class.continue_trace(trace_headers, name: 'test') do
          block_called = true
        end

        expect(block_called).to be true
      end
    end
  end

  describe 'header key constants' do
    it 'defines SENTRY_TRACE_HEADER' do
      expect(described_class::SENTRY_TRACE_HEADER).to eq('sentry-trace')
    end

    it 'defines BAGGAGE_HEADER' do
      expect(described_class::BAGGAGE_HEADER).to eq('baggage')
    end
  end
end
