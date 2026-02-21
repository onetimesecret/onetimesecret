# apps/web/auth/spec/integration/basic_auth_logic_base_spec.rb
#
# frozen_string_literal: true

# Integration test: Logic::Base initialization with BasicAuth session values.
#
# When BasicAuth succeeds, StrategyResult.session is {} (empty hash).
# This verifies Logic::Base handles that contract without crashing.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/integration/basic_auth_logic_base_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'

RSpec.describe Onetime::Logic::Base, 'with BasicAuth session contract', type: :integration do
  include_context 'strategy test'

  # Build a StrategyResult that mirrors what BasicAuthStrategy returns:
  # session is {}, user is the authenticated Customer, auth_method is 'basic_auth'.
  let(:strategy_result) do
    build_strategy_result(
      session: {},
      user: test_customer,
      auth_method: 'basic_auth',
      strategy_name: 'basicauth',
      metadata: {}
    )
  end

  # Logic::Base.new(strategy_result, params, locale)
  # Pass empty params hash and nil locale for minimal construction.
  let(:logic) { described_class.new(strategy_result, {}) }

  # -----------------------------------------------------------------
  # Core contract: no errors during initialization
  # -----------------------------------------------------------------
  describe 'initialization' do
    it 'does not raise when session is an empty hash' do
      expect { logic }.not_to raise_error
    end
  end

  # -----------------------------------------------------------------
  # @sess reflects the empty-hash session contract
  # -----------------------------------------------------------------
  describe '#sess' do
    it 'is an empty hash' do
      expect(logic.sess).to eq({})
    end

    it 'returns nil for bracket access on any key' do
      expect(logic.sess['anything']).to be_nil
    end

    it 'returns nil for sess["authenticated"] (not true)' do
      expect(logic.sess['authenticated']).to be_nil
    end
  end

  # -----------------------------------------------------------------
  # @cust is the Customer instance from the StrategyResult
  # -----------------------------------------------------------------
  describe '#cust' do
    it 'is a Customer instance' do
      expect(logic.cust).to be_a(Onetime::Customer)
    end

    it 'matches the test customer' do
      expect(logic.cust.custid).to eq(test_customer.custid)
    end
  end
end
