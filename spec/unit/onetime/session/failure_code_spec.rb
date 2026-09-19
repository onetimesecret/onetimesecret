# spec/unit/onetime/session/failure_code_spec.rb
#
# frozen_string_literal: true

# The wire `code` on a session-authentication refusal is the evaluator reason
# verbatim (#4462). This spec is what keeps a new evaluator reason from
# shipping without a deliberately chosen scope.

require 'spec_helper'
require 'onetime/session/failure_code'

RSpec.describe Onetime::SessionFailureCode do
  let(:refusal_reasons) { Onetime::CustomerSessionEvaluator::REASONS - [:authenticated] }

  it 'codes every evaluator refusal, and nothing else' do
    expect(described_class::CODES.keys).to match_array(refusal_reasons)
  end

  it 'uses the evaluator reason verbatim as the code' do
    described_class::CODES.each do |reason, entry|
      expect(entry['code']).to eq(reason.to_s)
    end
  end

  it 'gives every code exactly one known scope' do
    described_class::CODES.each_value do |entry|
      expect(entry.keys).to eq(%w[code code_scope])
      expect(described_class::SCOPES).to include(entry['code_scope'])
    end
  end

  it 'scopes the outage reasons as verification_unavailable, never as a session rejection' do
    unavailable = described_class::CODES.select { |_r, e| e['code_scope'] == 'verification_unavailable' }
    expect(unavailable.keys).to contain_exactly(:active_session_unavailable, :customer_unavailable)
  end

  it 'scopes only the admin timeout as admin_session' do
    admin = described_class::CODES.select { |_r, e| e['code_scope'] == 'admin_session' }
    expect(admin.keys).to eq([:admin_session_expired])
  end

  it 'does not emit the reserved credential scope' do
    expect(described_class::SCOPES).not_to include('credential')
  end

  it 'keeps a typed verdict distinct across the boundary' do
    expect(described_class.for(:surface_mismatch)).to eq(
      'code' => 'surface_mismatch', 'code_scope' => 'customer_session',
    )
  end

  it 'accepts a String reason' do
    expect(described_class.for('stale_credentials')['code']).to eq('stale_credentials')
  end

  it 'returns a mergeable empty Hash for a success, nil, or unknown reason' do
    expect(described_class.for(:authenticated)).to eq({})
    expect(described_class.for(nil)).to eq({})
    expect(described_class.for(:no_such_reason)).to eq({})
  end

  # The frontend's copy of the table. Both halves must change together; this
  # is the check that fails when only one does.
  describe 'parity with src/schemas/contracts/session-failure.ts' do
    let(:source) { File.read(File.join(Onetime::HOME, 'src/schemas/contracts/session-failure.ts')) }

    it 'lists the same codes with the same scopes' do
      block    = source[/export const SESSION_FAILURE_CODES = \{(.*?)\} as const/m, 1]
      frontend = block.scan(/^\s*(\w+): '(\w+)',$/).to_h

      expect(frontend).to eq(described_class::CODES.to_h { |reason, entry| [reason.to_s, entry['code_scope']] })
    end

    it 'lists the same emitted scopes' do
      block = source[/export const sessionFailureScopeValues = \[(.*?)\] as const/m, 1]

      expect(block.scan(/^\s*'(\w+)',$/).flatten).to match_array(described_class::SCOPES)
    end
  end

  it 'is deeply frozen so a caller cannot edit the contract at runtime' do
    expect(described_class::CODES).to be_frozen
    expect(described_class::CODES.values).to all(be_frozen)
  end
end
