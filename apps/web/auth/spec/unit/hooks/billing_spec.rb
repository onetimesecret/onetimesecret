# apps/web/auth/spec/unit/hooks/billing_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Unit Tests for Billing::extract_pending_plan_intent
# =============================================================================
#
# WHAT THIS TESTS:
#   The pending_plan_intent extraction logic in Auth::Config::Hooks::Billing.
#   Tests the module method directly with mock customer objects.
#
# SCOPE:
#   These are pure unit tests that call the extract_pending_plan_intent module
#   method directly with mock objects. They verify the method's logic in
#   isolation: JSON parsing, field extraction, clearing via delete!, and
#   error handling.
#
#   For true HTTP integration tests that exercise the full Rodauth login stack
#   (making actual POST /login requests and verifying billing_redirect in the
#   JSON response), see:
#
#     apps/web/auth/spec/integration/pending_plan_intent_flow_spec.rb
#     → describe 'HTTP integration: login with pending_plan_intent fallback'
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/unit/hooks/billing_spec.rb
#
# =============================================================================

require 'rspec'
require 'json'

# Define the namespace hierarchy before loading the module
module Auth; end
module Auth::Config; end
module Auth::Config::Hooks; end

# Load the actual production module
require_relative '../../../config/hooks/billing'

RSpec.describe Auth::Config::Hooks::Billing do
  describe '.extract_pending_plan_intent' do
    # Mock Familia::StringKey behavior matching production
    class MockStringKey
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def to_s
        @value.to_s
      end

      def delete!
        @value = nil
      end
    end

    # Mock customer with pending_plan_intent field matching Familia interface
    class MockCustomer
      attr_reader :pending_plan_intent

      def initialize(intent_value = nil)
        @pending_plan_intent = MockStringKey.new(intent_value)
      end
    end

    context 'when customer has valid pending_plan_intent JSON' do
      let(:intent_json) { { 'product' => 'identity_plus_v1', 'interval' => 'monthly' }.to_json }
      let(:customer) { MockCustomer.new(intent_json) }

      it 'returns [product, interval] tuple' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect(product).to eq('identity_plus_v1')
        expect(interval).to eq('monthly')
      end

      it 'clears pending_plan_intent via delete! (single-use)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to be_nil
      end
    end

    context 'when customer is nil' do
      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(nil)

        expect(product).to be_nil
        expect(interval).to be_nil
      end
    end

    context 'when pending_plan_intent is empty string' do
      let(:customer) { MockCustomer.new('') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect(product).to be_nil
        expect(interval).to be_nil
      end
    end

    context 'when pending_plan_intent is whitespace only' do
      let(:customer) { MockCustomer.new('   ') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect(product).to be_nil
        expect(interval).to be_nil
      end
    end

    context 'when pending_plan_intent contains invalid JSON' do
      let(:customer) { MockCustomer.new('not-valid-json{{') }
      let(:logged_errors) { [] }
      let(:logger) { ->(e) { logged_errors << e } }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer, logger: logger)

        expect(product).to be_nil
        expect(interval).to be_nil
      end

      it 'calls logger with the parse error' do
        described_class.extract_pending_plan_intent(customer, logger: logger)

        expect(logged_errors.size).to eq(1)
        expect(logged_errors.first).to be_a(JSON::ParserError)
      end
    end

    context 'when pending_plan_intent JSON is missing required fields' do
      let(:intent_json) { { 'product' => 'identity_plus_v1' }.to_json }
      let(:customer) { MockCustomer.new(intent_json) }

      it 'returns partial data (product present, interval nil)' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect(product).to eq('identity_plus_v1')
        expect(interval).to be_nil
      end
    end

    context 'when pending_plan_intent has extra fields' do
      let(:intent_json) do
        {
          'product' => 'team_plus_v1',
          'interval' => 'yearly',
          'captured_at' => '2024-01-15T10:30:00Z',
          'source' => 'pricing_page',
        }.to_json
      end
      let(:customer) { MockCustomer.new(intent_json) }

      it 'extracts only product and interval' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect(product).to eq('team_plus_v1')
        expect(interval).to eq('yearly')
      end
    end

    # =========================================================================
    # Non-Hash JSON types: graceful handling without TypeError
    # =========================================================================
    # These test the guard added in billing.rb line 68:
    #   return [nil, nil] unless intent.is_a?(Hash)
    # Previously, non-Hash JSON would crash with TypeError on field access.
    # Now returns [nil, nil] and preserves intent for debugging (no delete!).

    context 'when pending_plan_intent contains JSON array (empty)' do
      let(:customer) { MockCustomer.new('[]') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect([product, interval]).to eq([nil, nil])
      end

      it 'does NOT call delete! (preserves intent for debugging)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to eq('[]')
      end
    end

    context 'when pending_plan_intent contains JSON array (non-empty)' do
      let(:customer) { MockCustomer.new('[1, 2, 3]') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect([product, interval]).to eq([nil, nil])
      end

      it 'does NOT call delete! (preserves intent for debugging)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to eq('[1, 2, 3]')
      end
    end

    context 'when pending_plan_intent contains JSON string' do
      let(:customer) { MockCustomer.new('"just a string"') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect([product, interval]).to eq([nil, nil])
      end

      it 'does NOT call delete! (preserves intent for debugging)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to eq('"just a string"')
      end
    end

    context 'when pending_plan_intent contains JSON null' do
      let(:customer) { MockCustomer.new('null') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect([product, interval]).to eq([nil, nil])
      end

      it 'does NOT call delete! (preserves intent for debugging)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to eq('null')
      end
    end

    context 'when pending_plan_intent contains JSON number' do
      let(:customer) { MockCustomer.new('42') }

      it 'returns [nil, nil]' do
        product, interval = described_class.extract_pending_plan_intent(customer)

        expect([product, interval]).to eq([nil, nil])
      end

      it 'does NOT call delete! (preserves intent for debugging)' do
        described_class.extract_pending_plan_intent(customer)

        expect(customer.pending_plan_intent.value).to eq('42')
      end
    end
  end
end
