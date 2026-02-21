# apps/web/auth/spec/integration/generate_api_token_basic_auth_spec.rb
#
# frozen_string_literal: true

# Integration test: GenerateAPIToken is session-only.
#
# POST /apitoken uses auth=sessionauth (no basicauth). The logic layer
# requires sess['authenticated'] == true which only session-based auth
# provides. This spec confirms that contract and verifies the route
# restriction is consistent with the logic.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/integration/generate_api_token_basic_auth_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'

RSpec.describe 'GenerateAPIToken session-only auth', type: :integration do
  include_context 'strategy test'

  # -------------------------------------------------------------------
  # Simulate what BasicAuth would produce (not reachable via route, but
  # useful for demonstrating why session-only is correct).
  # -------------------------------------------------------------------
  let(:basic_auth_result) do
    build_strategy_result(
      session: {},
      user: test_customer,
      auth_method: 'basic_auth',
      strategy_name: 'BasicAuthStrategy',
      metadata: { ip: '127.0.0.1', user_agent: 'Test/1.0', auth_type: 'basic' },
    )
  end

  let(:session_auth_result) do
    build_strategy_result(
      session: {
        'authenticated' => true,
        'external_id' => test_customer.extid,
        'email' => test_customer.email,
      },
      user: test_customer,
      auth_method: 'sessionauth',
      strategy_name: 'SessionAuthStrategy',
      metadata: { ip: '127.0.0.1', user_agent: 'Test/1.0' },
    )
  end

  # -------------------------------------------------------------------
  # Route restriction: POST /apitoken is session-only
  # -------------------------------------------------------------------
  describe 'route restriction' do
    it 'POST /apitoken route uses auth=sessionauth only' do
      routes_file = File.expand_path('../../../../api/account/routes.txt', __dir__)
      apitoken_line = File.readlines(routes_file).find { |l| l.include?('/apitoken') }
      expect(apitoken_line).to include('auth=sessionauth')
      expect(apitoken_line).not_to include('basicauth')
    end
  end

  # -------------------------------------------------------------------
  # Logic layer requires session authentication
  # -------------------------------------------------------------------
  describe 'raise_concerns authentication check' do
    before do
      require 'account/logic'
    end

    it 'accepts SessionAuth sessions' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(session_auth_result, {})
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'rejects empty sessions (BasicAuth would produce this)' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(basic_auth_result, {})
      expect { logic.raise_concerns }.to raise_error(OT::FormError)
    end

    it 'rejects because sess["authenticated"] is nil for empty sessions' do
      sess = basic_auth_result.session
      expect(sess['authenticated']).to be_nil
    end
  end
end
