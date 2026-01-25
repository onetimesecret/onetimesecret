# spec/unit/onetime/logic/guest_route_gating_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/logic/guest_route_gating'

# Unit tests for GuestRouteGating module
#
# Tests the module methods directly without requiring full logic class setup.
# This complements the integration tests in spec/integration/api/v3/guest_route_gating_spec.rb
# by testing edge cases and module behavior in isolation.
#
RSpec.describe Onetime::Logic::GuestRouteGating do
  # Create a test class that includes the module
  let(:test_class) do
    Class.new do
      include Onetime::Logic::GuestRouteGating

      attr_accessor :cust, :strategy_result

      def initialize(cust:, strategy_result:)
        @cust = cust
        @strategy_result = strategy_result
      end
    end
  end

  let(:anonymous_customer) do
    double('Customer', anonymous?: true)
  end

  let(:authenticated_customer) do
    double('Customer', anonymous?: false, custid: 'test@example.com')
  end

  let(:noauth_strategy) do
    double('StrategyResult', auth_method: 'noauth')
  end

  let(:apikey_strategy) do
    double('StrategyResult', auth_method: 'apikey')
  end

  let(:session_strategy) do
    double('StrategyResult', auth_method: 'session')
  end

  # No boot! call needed - spec_helper already loads config
  # and unit tests shouldn't require full boot infrastructure

  describe '#require_guest_route_enabled!' do
    context 'with fully enabled config' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {
              'api' => {
                'guest_routes' => {
                  'enabled' => true,
                  'conceal' => true,
                  'generate' => true,
                  'reveal' => true,
                  'burn' => true,
                  'show' => true,
                  'receipt' => true,
                },
              },
            },
          },
        })
      end

      it 'returns true for guest context with all operations enabled' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect(instance.require_guest_route_enabled!(:conceal)).to be true
        expect(instance.require_guest_route_enabled!(:generate)).to be true
        expect(instance.require_guest_route_enabled!(:reveal)).to be true
        expect(instance.require_guest_route_enabled!(:burn)).to be true
      end

      it 'accepts string operation names' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect(instance.require_guest_route_enabled!('conceal')).to be true
      end
    end

    context 'with globally disabled config' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {
              'api' => {
                'guest_routes' => {
                  'enabled' => false,
                  'conceal' => true,
                  'generate' => true,
                },
              },
            },
          },
        })
      end

      it 'raises GuestRoutesDisabled for guest context' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled) do |error|
          expect(error.code).to eq('GUEST_ROUTES_DISABLED')
          expect(error.message).to eq('Guest API access is disabled')
        end
      end

      it 'returns true for authenticated context (bypasses check)' do
        instance = test_class.new(cust: authenticated_customer, strategy_result: apikey_strategy)

        expect(instance.require_guest_route_enabled!(:conceal)).to be true
      end
    end

    context 'with operation-specific disabled config' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {
              'api' => {
                'guest_routes' => {
                  'enabled' => true,
                  'conceal' => false,
                  'generate' => true,
                },
              },
            },
          },
        })
      end

      it 'raises GuestRoutesDisabled with operation-specific code' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled) do |error|
          expect(error.code).to eq('GUEST_CONCEAL_DISABLED')
          expect(error.message).to eq('Guest conceal is disabled')
        end
      end

      it 'allows enabled operations' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect(instance.require_guest_route_enabled!(:generate)).to be true
      end
    end

    context 'with nil strategy_result' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {
              'api' => {
                'guest_routes' => { 'enabled' => false },
              },
            },
          },
        })
      end

      it 'treats nil strategy_result as non-guest (safe default)' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: nil)

        # When strategy_result is nil, auth_method is nil, so noauth check fails
        # This means guest_context? returns false, bypassing the check
        expect(instance.require_guest_route_enabled!(:conceal)).to be true
      end
    end
  end

  describe 'guest_context? (private method via behavior)' do
    before do
      allow(OT).to receive(:conf).and_return({
        'site' => {
          'interface' => {
            'api' => {
              'guest_routes' => { 'enabled' => false },
            },
          },
        },
      })
    end

    it 'requires BOTH anonymous customer AND noauth strategy' do
      # Test all four combinations
      combinations = [
        { cust: anonymous_customer, strategy: noauth_strategy, expected_guest: true },
        { cust: anonymous_customer, strategy: apikey_strategy, expected_guest: false },
        { cust: authenticated_customer, strategy: noauth_strategy, expected_guest: false },
        { cust: authenticated_customer, strategy: apikey_strategy, expected_guest: false },
      ]

      combinations.each do |combo|
        instance = test_class.new(cust: combo[:cust], strategy_result: combo[:strategy])

        if combo[:expected_guest]
          # Should raise because guest routes are disabled
          expect {
            instance.require_guest_route_enabled!(:conceal)
          }.to raise_error(Onetime::GuestRoutesDisabled),
               "Expected guest context for anonymous=#{combo[:cust].anonymous?}, auth=#{combo[:strategy].auth_method}"
        else
          # Should NOT raise because not in guest context
          expect(instance.require_guest_route_enabled!(:conceal)).to be true
        end
      end
    end
  end

  describe 'Onetime::GuestRoutesDisabled exception' do
    it 'inherits from Onetime::Forbidden' do
      expect(Onetime::GuestRoutesDisabled.ancestors).to include(Onetime::Forbidden)
    end

    it 'has default message' do
      error = Onetime::GuestRoutesDisabled.new
      expect(error.message).to eq('Guest API access is disabled')
    end

    it 'has default code' do
      error = Onetime::GuestRoutesDisabled.new
      expect(error.code).to eq('GUEST_ROUTES_DISABLED')
    end

    it 'accepts custom message and code' do
      error = Onetime::GuestRoutesDisabled.new('Custom message', code: 'CUSTOM_CODE')
      expect(error.message).to eq('Custom message')
      expect(error.code).to eq('CUSTOM_CODE')
    end

    it 'serializes to hash with message and code' do
      error = Onetime::GuestRoutesDisabled.new('Test message', code: 'TEST_CODE')
      hash = error.to_h

      expect(hash).to eq({
        message: 'Test message',
        code: 'TEST_CODE',
      })
    end
  end

  describe 'config edge cases' do
    context 'when config path is partially missing' do
      it 'handles missing site key' do
        allow(OT).to receive(:conf).and_return({})

        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        # Missing config means guest_routes_config returns {}
        # Empty hash has no 'enabled' key, so check fails
        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled)
      end

      it 'handles missing interface key' do
        allow(OT).to receive(:conf).and_return({
          'site' => {},
        })

        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled)
      end

      it 'handles missing api key' do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {},
          },
        })

        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled)
      end
    end

    context 'when operation key is missing from config' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {
            'interface' => {
              'api' => {
                'guest_routes' => {
                  'enabled' => true,
                  # 'conceal' key is missing
                },
              },
            },
          },
        })
      end

      it 'treats missing operation as disabled (nil is falsy)' do
        instance = test_class.new(cust: anonymous_customer, strategy_result: noauth_strategy)

        expect {
          instance.require_guest_route_enabled!(:conceal)
        }.to raise_error(Onetime::GuestRoutesDisabled) do |error|
          expect(error.code).to eq('GUEST_CONCEAL_DISABLED')
        end
      end
    end
  end
end
