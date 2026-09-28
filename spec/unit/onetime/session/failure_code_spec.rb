# spec/unit/onetime/session/failure_code_spec.rb
#
# frozen_string_literal: true

# The wire `code` on an authentication refusal is the reason verbatim: the
# evaluator's for a session refusal (#4462), the credential vocabulary's for a
# rejected credential (#4469). This spec is what keeps a new evaluator reason
# from shipping without a deliberately chosen scope, and the credential
# vocabulary from growing without a deliberate decision.

require 'spec_helper'
require 'onetime/session/failure_code'

RSpec.describe Onetime::SessionFailureCode do
  let(:refusal_reasons) { Onetime::CustomerSessionEvaluator::REASONS - [:authenticated] }
  let(:credential_reasons) { described_class::CREDENTIAL_REASON_SCOPES.keys }

  it 'codes every evaluator refusal and every credential reason, and nothing else' do
    expect(described_class::SESSION_REASON_SCOPES.keys).to match_array(refusal_reasons)
    expect(described_class::CODES.keys).to match_array(refusal_reasons + credential_reasons)
  end

  it 'keeps the session and credential vocabularies disjoint' do
    expect(refusal_reasons & credential_reasons).to be_empty
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

  # #4469: the credential vocabulary, at the granularity of the messages the
  # surfaces already send. A code that told an unknown account from a wrong
  # password would be an enumeration surface the message does not have.
  it 'scopes exactly the credential vocabulary as credential' do
    credential = described_class::CODES.select { |_r, e| e['code_scope'] == 'credential' }
    expect(credential.keys).to contain_exactly(:invalid_credentials, :api_key_invalid, :suspended_credentials)
  end

  it 'knows which reasons are credential refusals' do
    expect(described_class.credential?(:invalid_credentials)).to be true
    expect(described_class.credential?('api_key_invalid')).to be true
    expect(described_class.credential?(:account_suspended)).to be false
    expect(described_class.credential?(nil)).to be false
  end

  describe '.stash and .forget' do
    it 'writes and withdraws the reason under ENV_KEY, last writer winning' do
      env = {}
      described_class.stash(env, :session_missing)
      described_class.stash(env, :api_key_invalid)
      expect(env).to eq(described_class::ENV_KEY => :api_key_invalid)

      described_class.forget(env)
      expect(env).to be_empty
    end

    it 'ignores a nil or non-Hash env (bare strategy calls)' do
      expect { described_class.stash(nil, :api_key_invalid) }.not_to raise_error
      expect { described_class.forget(nil) }.not_to raise_error
      expect { described_class.stash('not an env', :api_key_invalid) }.not_to raise_error
    end
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

  # #4461: refusal codes and request ids are logged; credentials and session
  # identifiers are not.
  describe '.log_refusal' do
    let(:logger) { instance_double(SemanticLogger::Logger, debug: nil, info: nil, warn: nil) }
    let(:sid) { 'c9803eb969a503006ddcca0b3460b47b9c0f9fafe6a4bb100de20efa1d7d3655' }
    let(:env) do
      {
        'HTTP_X_REQUEST_ID' => 'req-4461',
        'HTTP_COOKIE' => "onetime.session=#{sid}",
        'HTTP_AUTHORIZATION' => 'Basic dXNlcjpzZWNyZXQ=',
        'HTTP_X_CSRF_TOKEN' => 'csrf-token-value',
        'PATH_INFO' => '/api/v2/secret/abc123secretkey',
        'rack.session' => { 'external_id' => 'ur_someone', 'account_id' => 42 },
        'otto.route_definition' => Otto::RouteDefinition.new('GET', '/api/v2/secret/:key', 'V2::Secrets#show auth=sessionauth'),
      }
    end

    before { allow(Onetime).to receive(:auth_logger).and_return(logger) }

    it 'logs the code, its scope, the request id and the route pattern' do
      described_class.log_refusal(:active_session_revoked, env)

      expect(logger).to have_received(:info).with(
        'Session refused',
        { code: 'active_session_revoked', code_scope: 'customer_session', request_id: 'req-4461', route: '/api/v2/secret/:key' },
      )
    end

    it 'logs nothing that could be replayed or that names the secret in the path' do
      logged = []
      allow(logger).to receive(:info) { |*args| logged << args.inspect }

      described_class.log_refusal(:stale_credentials, env)

      line = logged.join
      expect(line).not_to be_empty
      [sid, 'dXNlcjpzZWNyZXQ', 'csrf-token-value', 'abc123secretkey', 'ur_someone'].each do |credential|
        expect(line).not_to include(credential)
      end
    end

    it 'logs a verification outage at warn: it refuses sessions that may be valid' do
      described_class.log_refusal(:active_session_unavailable, env)

      expect(logger).to have_received(:warn).with('Session refused', hash_including(code_scope: 'verification_unavailable'))
    end

    it 'logs a visitor without a session, and a login in progress, at debug' do
      described_class::ROUTINE_REASONS.each { |reason| described_class.log_refusal(reason, env) }

      expect(logger).to have_received(:debug).exactly(3).times
      expect(logger).not_to have_received(:info)
    end

    it 'logs every session reason exactly once' do
      codes = []
      %i[debug info warn].each do |level|
        allow(logger).to receive(level) { |_message, payload| codes << payload.fetch(:code) }
      end

      described_class::CODES.each_key { |reason| described_class.log_refusal(reason, env) }

      expect(codes).to match_array(described_class::SESSION_REASON_SCOPES.keys.map(&:to_s))
    end

    # A rejected credential is recorded by the surface that rejected it; a
    # `Session refused` line for it would claim a session was examined.
    it 'is silent for a credential refusal' do
      described_class::CREDENTIAL_REASON_SCOPES.each_key { |reason| described_class.log_refusal(reason, env) }

      %i[debug info warn].each { |level| expect(logger).not_to have_received(level) }
    end

    it 'omits what it does not have instead of logging nil' do
      described_class.log_refusal(:account_suspended, {})

      expect(logger).to have_received(:info).with('Session refused', { code: 'account_suspended', code_scope: 'customer_session' })
    end

    it 'is silent for a success or an unknown reason' do
      described_class.log_refusal(:authenticated, env)
      described_class.log_refusal(:no_such_reason, env)
      described_class.log_refusal(nil, env)

      %i[debug info warn].each { |level| expect(logger).not_to have_received(level) }
    end

    it 'never raises, whatever the logger does' do
      allow(logger).to receive(:info).and_raise(IOError, 'sink closed')

      expect { described_class.log_refusal(:account_suspended, env) }.not_to raise_error
    end
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
