# apps/web/auth/spec/integration/generate_api_token_basic_auth_spec.rb
#
# frozen_string_literal: true

# Integration test: GenerateAPIToken reachability via BasicAuth.
#
# Documents a known gap: POST /apitoken allows basicauth, but
# GenerateAPIToken#raise_concerns checks sess['authenticated'] == true.
# With BasicAuth, sess is {}, so this check fails.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/integration/generate_api_token_basic_auth_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'

RSpec.describe 'GenerateAPIToken reachability via BasicAuth', type: :integration do
  include_context 'strategy test'

  # -------------------------------------------------------------------
  # Simulate what BasicAuth produces: an authenticated StrategyResult
  # with session: {} and a real Customer.
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

  # For contrast: what SessionAuth produces
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
  # The session contract gap
  # -------------------------------------------------------------------
  describe 'session contract: BasicAuth vs SessionAuth' do
    it 'BasicAuth result is authenticated' do
      expect(basic_auth_result.authenticated?).to be true
    end

    it 'BasicAuth session is {}' do
      expect(basic_auth_result.session).to eq({})
    end

    it "BasicAuth session['authenticated'] is nil, not true" do
      # This is the crux of the gap: the session hash is empty,
      # so bracket access returns nil for any key.
      sess = basic_auth_result.session
      expect(sess['authenticated']).to be_nil
    end

    it "SessionAuth session['authenticated'] is true" do
      sess = session_auth_result.session
      expect(sess['authenticated']).to eq(true)
    end

    it 'the authenticated check that raise_concerns uses rejects BasicAuth sessions' do
      # GenerateAPIToken#raise_concerns (line 15) does:
      #   authenticated = @sess['authenticated'] == true
      # Replicate that logic here to show the mismatch.
      basic_auth_sess = basic_auth_result.session
      authenticated = basic_auth_sess['authenticated'] == true
      expect(authenticated).to be false
    end

    it 'the same check passes for SessionAuth sessions' do
      session_auth_sess = session_auth_result.session
      authenticated = session_auth_sess['authenticated'] == true
      expect(authenticated).to be true
    end
  end

  # -------------------------------------------------------------------
  # Attempt to instantiate GenerateAPIToken with a BasicAuth result
  # -------------------------------------------------------------------
  describe 'GenerateAPIToken instantiation with BasicAuth result' do
    before do
      # Load the AccountAPI logic classes. After Onetime.boot!,
      # apps/api is on $LOAD_PATH so 'account/logic' resolves to
      # apps/api/account/logic.rb which pulls in all logic classes.
      require 'account/logic'
    end

    it 'can be instantiated with a BasicAuth StrategyResult' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(basic_auth_result, {})
      expect(logic).to be_a(AccountAPI::Logic::Account::GenerateAPIToken)
      expect(logic.cust.custid).to eq(test_customer.custid)
    end

    it 'sess is the empty hash from BasicAuth' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(basic_auth_result, {})
      expect(logic.sess).to eq({})
    end

    # This is the documented gap: raise_concerns rejects BasicAuth
    # even though the route declares auth=sessionauth,basicauth.
    pending 'raise_concerns should accept BasicAuth-authenticated requests (architectural gap)' do
      # Route POST /apitoken has auth=sessionauth,basicauth.
      # BasicAuth authenticates successfully, but raise_concerns
      # checks @sess['authenticated'] == true, which is nil for
      # BasicAuth sessions (sess is {}).
      #
      # Until the logic is updated to check StrategyResult#authenticated?
      # or the session contract is enriched, BasicAuth callers are
      # rejected at the logic layer despite passing the auth layer.
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(basic_auth_result, {})
      expect { logic.raise_concerns }.not_to raise_error
    end

    it 'raise_concerns rejects BasicAuth sessions (current behavior)' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(basic_auth_result, {})
      expect { logic.raise_concerns }.to raise_error(OT::FormError)
    end

    it 'raise_concerns accepts SessionAuth sessions' do
      logic = AccountAPI::Logic::Account::GenerateAPIToken.new(session_auth_result, {})
      expect { logic.raise_concerns }.not_to raise_error
    end
  end
end
