# apps/web/billing/spec/errors_spec.rb
#
# frozen_string_literal: true

# Unit tests for Billing error classes
#
# Tests cover:
# - CircuitOpenError attributes and inheritance
# - OpsProblem base class
# - ForbiddenOperation error

require_relative 'support/billing_spec_helper'
require_relative '../errors'

RSpec.describe 'Billing Errors', type: :billing do
  describe Billing::OpsProblem do
    it 'inherits from Onetime::Problem' do
      expect(Billing::OpsProblem.superclass).to eq(Onetime::Problem)
    end

    it 'can be instantiated with a message' do
      error = Billing::OpsProblem.new('Something went wrong')
      expect(error.message).to eq('Something went wrong')
    end

    it 'can be raised and caught' do
      expect do
        raise Billing::OpsProblem, 'Test error'
      end.to raise_error(Billing::OpsProblem, 'Test error')
    end
  end

  describe Billing::CircuitOpenError do
    describe 'inheritance' do
      it 'inherits from Billing::OpsProblem' do
        expect(Billing::CircuitOpenError.superclass).to eq(Billing::OpsProblem)
      end

      it 'can be caught as OpsProblem' do
        expect do
          raise Billing::CircuitOpenError.new
        end.to raise_error(Billing::OpsProblem)
      end

      it 'can be caught as Onetime::Problem' do
        expect do
          raise Billing::CircuitOpenError.new
        end.to raise_error(Onetime::Problem)
      end
    end

    describe '#retry_after attribute' do
      it 'is accessible' do
        error = Billing::CircuitOpenError.new(retry_after: 45)
        expect(error.retry_after).to eq(45)
      end

      it 'defaults to nil when not provided' do
        error = Billing::CircuitOpenError.new
        expect(error.retry_after).to be_nil
      end

      it 'accepts integer values' do
        error = Billing::CircuitOpenError.new(retry_after: 60)
        expect(error.retry_after).to eq(60)
      end

      it 'accepts zero' do
        error = Billing::CircuitOpenError.new(retry_after: 0)
        expect(error.retry_after).to eq(0)
      end
    end

    describe 'default message' do
      it 'has default message when none provided' do
        error = Billing::CircuitOpenError.new
        expect(error.message).to eq('Stripe circuit breaker is open')
      end
    end

    describe 'custom message with retry_after' do
      it 'accepts custom message' do
        error = Billing::CircuitOpenError.new('Custom circuit open message')
        expect(error.message).to eq('Custom circuit open message')
      end

      it 'accepts custom message with retry_after' do
        error = Billing::CircuitOpenError.new(
          'Circuit open, retry in 30 seconds',
          retry_after: 30,
        )
        expect(error.message).to eq('Circuit open, retry in 30 seconds')
        expect(error.retry_after).to eq(30)
      end

      it 'preserves retry_after when raised and caught' do
        caught_error = nil
        begin
          raise Billing::CircuitOpenError.new('Test', retry_after: 25)
        rescue Billing::CircuitOpenError => e
          caught_error = e
        end

        expect(caught_error.retry_after).to eq(25)
        expect(caught_error.message).to eq('Test')
      end
    end

    describe 'usage patterns' do
      it 'works with formatted failure count message' do
        failure_count = 5
        retry_after = 45

        error = Billing::CircuitOpenError.new(
          "Stripe circuit breaker is open (#{failure_count} failures). Retry after #{retry_after}s.",
          retry_after: retry_after,
        )

        expect(error.message).to include('5 failures')
        expect(error.message).to include('Retry after 45s')
        expect(error.retry_after).to eq(45)
      end
    end
  end

  describe Billing::ForbiddenOperation do
    it 'inherits from RuntimeError' do
      expect(Billing::ForbiddenOperation.superclass).to eq(RuntimeError)
    end

    it 'has EXIT_CODE constant' do
      expect(Billing::ForbiddenOperation::EXIT_CODE).to eq(87)
    end

    it 'has exit_code method' do
      error = Billing::ForbiddenOperation.new('Cannot update immutable price')
      expect(error.exit_code).to eq(87)
    end

    it 'can be raised with message' do
      expect do
        raise Billing::ForbiddenOperation, 'Price is immutable'
      end.to raise_error(Billing::ForbiddenOperation, 'Price is immutable')
    end
  end
end
