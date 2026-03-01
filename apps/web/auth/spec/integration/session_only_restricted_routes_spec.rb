# apps/web/auth/spec/integration/session_only_restricted_routes_spec.rb
#
# frozen_string_literal: true

# Integration test: DestroyAccount and UpdateDomainContext are session-only.
#
# POST /destroy and POST /update-domain-context use auth=sessionauth
# (no basicauth). Both operations depend on session state:
#   - DestroyAccount calls sess.clear after deletion
#   - UpdateDomainContext writes sess['domain_context']
#
# This spec confirms the route restrictions and verifies that the session
# contract is consistent with session-only auth (BasicAuth produces an
# empty session hash that would make these operations unsafe).
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/integration/session_only_restricted_routes_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'

RSpec.describe 'Session-only restricted routes', type: :integration do
  include_context 'strategy test'

  let(:routes_file) do
    File.expand_path('../../../../api/account/routes.txt', __dir__)
  end

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

  before do
    require 'account/logic'
  end

  # =====================================================================
  # POST /destroy — DestroyAccount
  # =====================================================================
  describe 'POST /destroy (DestroyAccount)' do
    # -----------------------------------------------------------------
    # Route restriction: POST /destroy is session-only
    # -----------------------------------------------------------------
    describe 'route restriction' do
      it 'POST /destroy route uses auth=sessionauth only' do
        destroy_line = File.readlines(routes_file).find { |l| l.include?('/destroy') }
        expect(destroy_line).to include('auth=sessionauth')
        expect(destroy_line).not_to include('basicauth')
      end
    end

    # -----------------------------------------------------------------
    # Session contract: DestroyAccount depends on real session state
    # -----------------------------------------------------------------
    describe 'session contract' do
      it 'returns "unknown" for session_sid with empty BasicAuth session' do
        logic = AccountAPI::Logic::Account::DestroyAccount.new(basic_auth_result, {})
        expect(logic.session_sid).to eq('unknown')
      end

      it 'returns session sid from SessionAuth session' do
        session_with_sid = session_auth_result.session.merge('sid' => 'test-session-id')
        result = build_strategy_result(
          session: session_with_sid,
          user: test_customer,
          auth_method: 'sessionauth',
          strategy_name: 'SessionAuthStrategy',
          metadata: {},
        )
        logic = AccountAPI::Logic::Account::DestroyAccount.new(result, {})
        expect(logic.session_sid).to eq('test-session-id')
      end

      it 'sess.clear is a no-op on the empty BasicAuth session' do
        # DestroyAccount#process calls sess.clear to invalidate the
        # session after account deletion. With BasicAuth's empty hash,
        # this is a no-op — the session was never real.
        sess = basic_auth_result.session
        expect(sess).to eq({})
        sess.clear
        expect(sess).to eq({})
      end

      it 'sess.clear destroys session state for SessionAuth' do
        sess = session_auth_result.session
        expect(sess['authenticated']).to eq(true)
        expect(sess['email']).to eq(test_customer.email)
        sess.clear
        expect(sess).to eq({})
      end

      it 'sess["authenticated"] is nil for BasicAuth (empty session)' do
        logic = AccountAPI::Logic::Account::DestroyAccount.new(basic_auth_result, {})
        expect(logic.sess['authenticated']).to be_nil
      end

      it 'sess["authenticated"] is true for SessionAuth' do
        logic = AccountAPI::Logic::Account::DestroyAccount.new(session_auth_result, {})
        expect(logic.sess['authenticated']).to eq(true)
      end
    end
  end

  # =====================================================================
  # POST /update-domain-context — UpdateDomainContext
  # =====================================================================
  describe 'POST /update-domain-context (UpdateDomainContext)' do
    # -----------------------------------------------------------------
    # Route restriction: POST /update-domain-context is session-only
    # -----------------------------------------------------------------
    describe 'route restriction' do
      it 'POST /update-domain-context route uses auth=sessionauth only' do
        udc_line = File.readlines(routes_file).find { |l| l.include?('/update-domain-context') }
        expect(udc_line).to include('auth=sessionauth')
        expect(udc_line).not_to include('basicauth')
      end
    end

    # -----------------------------------------------------------------
    # Session contract: UpdateDomainContext writes to session
    # -----------------------------------------------------------------
    describe 'session contract' do
      it 'sess["domain_context"] is nil in empty BasicAuth session' do
        sess = basic_auth_result.session
        expect(sess['domain_context']).to be_nil
      end

      it 'rejects anonymous customers (BasicAuth degenerate case)' do
        anon_result = build_strategy_result(
          session: {},
          user: Onetime::Customer.anonymous,
          auth_method: 'basic_auth',
          strategy_name: 'BasicAuthStrategy',
          metadata: {},
        )
        logic = AccountAPI::Logic::Account::UpdateDomainContext.new(
          anon_result, { 'domain' => 'example.com' }
        )
        expect { logic.raise_concerns }.to raise_error(OT::Unauthorized)
      end

      it 'session writes on empty BasicAuth hash are ephemeral' do
        # UpdateDomainContext#perform_update does:
        #   sess['domain_context'] = new_domain_context
        # With BasicAuth's empty hash, this write goes to a transient
        # hash that is never persisted to the session store.
        sess = basic_auth_result.session
        sess['domain_context'] = 'example.com'
        # The write "succeeds" in-memory but the hash is ephemeral
        expect(sess['domain_context']).to eq('example.com')
        # The empty-hash contract from BasicAuth is now violated
        expect(sess).not_to be_empty
      end

      it 'session writes on SessionAuth hash persist state' do
        sess = session_auth_result.session
        sess['domain_context'] = 'example.com'
        expect(sess['domain_context']).to eq('example.com')
        # Session retains both auth state and the new domain context
        expect(sess['authenticated']).to eq(true)
      end

      it 'returns "unknown" for session_sid with empty BasicAuth session' do
        logic = AccountAPI::Logic::Account::UpdateDomainContext.new(
          basic_auth_result, { 'domain' => 'example.com' }
        )
        expect(logic.session_sid).to eq('unknown')
      end
    end
  end
end
