# apps/web/auth/spec/support/shared_examples/session_contract_examples.rb
#
# frozen_string_literal: true

# Shared examples for the session contract that all auth strategies must satisfy.
#
# The calling spec must provide a `result` (via let or subject) that is a
# StrategyResult (Otto::Security::Authentication::StrategyResult).
#
# The critical invariant: session is NEVER nil. BasicAuth returns {},
# session-based strategies return the Rack session hash. Both must support
# bracket access so downstream consumers (Logic::Base, RequestHelpers) can
# safely index into session without raising.
#
# @example
#   describe SomeAuthStrategy do
#     let(:result) { ... }
#     include_examples 'a valid session contract'
#   end
RSpec.shared_examples 'a valid session contract' do
  it 'session is not nil' do
    expect(result.session).not_to be_nil
  end

  it 'session responds to bracket access' do
    expect(result.session).to respond_to(:[])
  end

  it 'session returns nil for nonexistent keys' do
    expect(result.session['nonexistent_key']).to be_nil
  end
end
