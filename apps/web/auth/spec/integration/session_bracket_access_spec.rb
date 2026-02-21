# apps/web/auth/spec/integration/session_bracket_access_spec.rb
#
# frozen_string_literal: true

# Integration test: session bracket access safety for BasicAuth's empty session.
#
# Logic classes reachable via basicauth routes use sess['key'] and sess['key']=.
# This verifies that {} (BasicAuth's session value) supports all these operations
# without raising NoMethodError or TypeError.
#
# Requires Valkey on port 2121 (pnpm run test:database:start).
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/integration/session_bracket_access_spec.rb

require_relative '../spec_helper'
require_relative '../support/strategy_test_context'

RSpec.describe 'Session bracket access safety for BasicAuth', type: :integration do
  include_context 'strategy test'

  let(:result) do
    build_strategy_result(
      session: {},
      user: test_customer,
      auth_method: 'basic_auth'
    )
  end

  let(:sess) { result.session }

  # Sanity: confirm the session is the empty hash we expect
  it 'session is an empty hash' do
    expect(sess).to eq({})
  end

  # ---------------------------------------------------------------------------
  # Read operations — Logic classes that do sess['key']
  # ---------------------------------------------------------------------------
  describe 'bracket reads on empty session' do
    it 'sess["domain_context"] returns nil (UpdateDomainContext, RemoveDomain)' do
      expect(sess['domain_context']).to be_nil
    end

    it 'sess["external_id"] returns nil (AuthenticationSerializer)' do
      expect(sess['external_id']).to be_nil
    end

    it 'sess["locale"] returns nil' do
      expect(sess['locale']).to be_nil
    end

    it 'arbitrary key returns nil without raising' do
      expect { sess['anything'] }.not_to raise_error
      expect(sess['anything']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Write operations — Logic classes that do sess['key'] = value
  # ---------------------------------------------------------------------------
  describe 'bracket writes on empty session' do
    it 'sess["domain_context"] = value succeeds (AddDomain)' do
      expect { sess['domain_context'] = 'example.com' }.not_to raise_error
      expect(sess['domain_context']).to eq('example.com')
    end

    it 'sess["locale"] = value succeeds (UpdateLocale)' do
      expect { sess['locale'] = 'fr' }.not_to raise_error
      expect(sess['locale']).to eq('fr')
    end

    it 'arbitrary key assignment succeeds' do
      expect { sess['new_key'] = 'new_value' }.not_to raise_error
      expect(sess['new_key']).to eq('new_value')
    end
  end

  # ---------------------------------------------------------------------------
  # Predicate operations — Logic classes that call methods on sess
  # ---------------------------------------------------------------------------
  describe 'predicate methods on empty session' do
    it 'sess.empty? returns true (AuthenticationSerializer)' do
      expect(sess.empty?).to be true
    end

    it 'sess responds to empty?' do
      expect(sess).to respond_to(:empty?)
    end

    it 'sess responds to []' do
      expect(sess).to respond_to(:[])
    end

    it 'sess responds to []=' do
      expect(sess).to respond_to(:[]=)
    end
  end

  # ---------------------------------------------------------------------------
  # Write-then-read round-trip — proves writes are not silently swallowed
  # ---------------------------------------------------------------------------
  describe 'write-then-read round-trip' do
    it 'written values are retrievable' do
      sess['domain_context'] = 'test.example.com'
      sess['locale'] = 'de'
      sess['external_id'] = 'ext_12345'

      expect(sess['domain_context']).to eq('test.example.com')
      expect(sess['locale']).to eq('de')
      expect(sess['external_id']).to eq('ext_12345')
    end

    it 'empty? becomes false after a write' do
      expect(sess.empty?).to be true
      sess['locale'] = 'en'
      expect(sess.empty?).to be false
    end
  end
end
