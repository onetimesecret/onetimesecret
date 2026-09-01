# spec/unit/onetime/middleware/impersonation_context_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/middleware/impersonation_context'

# Unit tests for the impersonation context + read-only guard.
#
# The guard is a POSITIVE LIST, so the interesting assertions are the ones that
# DENY: anything the list does not affirm must 403, including shapes nobody
# thought about (an odd verb, a mount-relative colonel path, a secret GET that
# is really a burn).
RSpec.describe Onetime::Middleware::ImpersonationContext do
  let(:now) { 1_756_700_000 }
  let(:observed) { {} }

  let(:downstream) do
    lambda do |_env|
      observed[:context] = Onetime::SessionImpersonation.context
      observed[:called]  = true
      [200, { 'content-type' => 'application/json' }, ['{}']]
    end
  end

  let(:middleware) { described_class.new(downstream) }

  let(:marker) do
    {
      'id' => 'imp_deadbeefdeadbeef',
      'target_extid' => 'ur_target',
      'target_email' => 'alice@example.com',
      'reason' => 'ticket #123',
      'started_at' => now,
      'expires_at' => now + Onetime::SessionImpersonation::TTL,
    }
  end

  let(:impersonating_session) do
    {
      'external_id' => 'ur_colonel',
      Onetime::SessionImpersonation::SESSION_KEY => marker,
    }
  end

  before do
    allow(Familia).to receive(:now).and_return(now)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    Onetime::SessionImpersonation.clear_context
  end

  after { Onetime::SessionImpersonation.clear_context }

  # SCRIPT_NAME + PATH_INFO, because the universal stack runs inside URLMap and
  # a PATH_INFO-only check goes dead for every mounted app.
  def env_for(method, script_name, path_info, session: impersonating_session, **extra)
    {
      'REQUEST_METHOD' => method,
      'SCRIPT_NAME' => script_name,
      'PATH_INFO' => path_info,
      'QUERY_STRING' => '',
      'rack.session' => session,
    }.merge(extra)
  end

  def json_error(body)
    JSON.parse(body.first)
  end

  describe 'context publication' do
    it 'publishes the marker plus the principal for the duration of the request' do
      middleware.call(env_for('GET', '', '/dashboard'))

      expect(observed[:context]).to include(
        'impersonation_id' => 'imp_deadbeefdeadbeef',
        'impersonator_extid' => 'ur_colonel',
        'target_extid' => 'ur_target',
        'target_email' => 'alice@example.com',
      )
    end

    it 'clears the context after the request' do
      middleware.call(env_for('GET', '', '/dashboard'))

      expect(Onetime::SessionImpersonation.context).to be_nil
    end

    it 'clears the context even when downstream raises' do
      boom = ->(_env) { raise 'boom' }

      expect { described_class.new(boom).call(env_for('GET', '', '/dashboard')) }
        .to raise_error('boom')
      expect(Onetime::SessionImpersonation.context).to be_nil
    end

    it 'publishes nothing for an ordinary session' do
      middleware.call(env_for('GET', '', '/dashboard', session: { 'external_id' => 'ur_alice' }))

      expect(observed[:context]).to be_nil
      expect(observed[:called]).to be true
    end

    it 'publishes nothing for a sessionless request' do
      middleware.call({ 'REQUEST_METHOD' => 'GET', 'SCRIPT_NAME' => '', 'PATH_INFO' => '/' })

      expect(observed[:context]).to be_nil
      expect(observed[:called]).to be true
    end
  end

  describe 'the positive list' do
    it 'allows a safe method on an ordinary path' do
      status, = middleware.call(env_for('GET', '', '/dashboard'))

      expect(status).to eq(200)
    end

    it 'allows a mount-relative API read' do
      status, = middleware.call(env_for('GET', '/api/v3', '/receipt/recent'))

      expect(status).to eq(200)
    end

    %w[HEAD OPTIONS].each do |verb|
      it "allows #{verb}" do
        status, = middleware.call(env_for(verb, '', '/dashboard'))

        expect(status).to eq(200)
      end
    end

    %w[POST PUT PATCH DELETE].each do |verb|
      it "denies #{verb} with the read-only error" do
        status, headers, body = middleware.call(env_for(verb, '/api/v3', '/secret/conceal'))

        expect(status).to eq(403)
        expect(headers['content-type']).to eq('application/json')
        expect(json_error(body)['error_code']).to eq('impersonation_read_only')
        expect(observed[:called]).to be_nil
      end
    end

    # The sharpest edge: Rodauth's account_id is still the COLONEL's.
    it 'denies a GET under /api/auth' do
      status, _headers, body = middleware.call(env_for('GET', '/api/auth', '/login'))

      expect(status).to eq(403)
      expect(json_error(body)['error_code']).to eq('impersonation_read_only')
    end

    it 'denies a GET under /auth' do
      status, = middleware.call(env_for('GET', '', '/auth/change-password'))

      expect(status).to eq(403)
    end

    it 'denies the colonel shell' do
      expect(middleware.call(env_for('GET', '', '/colonel')).first).to eq(403)
      expect(middleware.call(env_for('GET', '', '/colonel/customers')).first).to eq(403)
    end

    it 'denies the colonel API at its mount point' do
      expect(middleware.call(env_for('GET', '/api/colonel', '/users')).first).to eq(403)
    end

    # Normalization is what makes the prefix check hold: the router dispatches
    # on the decoded path, so a raw-string comparison would let this through.
    it 'denies a percent-encoded colonel path' do
      expect(middleware.call(env_for('GET', '', '/%63olonel/customers')).first).to eq(403)
    end

    it 'does not deny paths that merely start with the same letters' do
      expect(middleware.call(env_for('GET', '', '/colonelize')).first).to eq(200)
      expect(middleware.call(env_for('GET', '/api/v2', '/authors')).first).to eq(200)
    end

    it 'allows the stop endpoint despite being a POST' do
      status, = middleware.call(env_for('POST', '/api/account', '/impersonation/stop'))

      expect(status).to eq(200)
      expect(observed[:called]).to be true
    end

    # GET /api/v2/secret/:id?continue=true CONSUMES the secret.
    it 'denies a secret GET carrying reveal intent' do
      env = env_for('GET', '/api/v2', '/secret/abc123', 'QUERY_STRING' => 'continue=true')

      status, _headers, body = middleware.call(env)

      expect(status).to eq(403)
      expect(json_error(body)['error_code']).to eq('impersonation_read_only')
    end

    it 'allows the same GET without reveal intent' do
      env = env_for('GET', '/api/v2', '/secret/abc123', 'QUERY_STRING' => 'continue=false')

      expect(middleware.call(env).first).to eq(200)
    end

    it 'serves an HTML denial to a page navigation' do
      env = env_for('POST', '', '/dashboard', 'HTTP_ACCEPT' => 'text/html,application/xhtml+xml')

      status, headers, body = middleware.call(env)

      expect(status).to eq(403)
      expect(headers['content-type']).to start_with('text/html')
      expect(body.first).to include('Read-only session')
    end

    it 'keeps the JSON contract for an API path even when the client accepts HTML' do
      env = env_for('POST', '/api/v3', '/secret/conceal', 'HTTP_ACCEPT' => 'text/html')

      status, headers, = middleware.call(env)

      expect(status).to eq(403)
      expect(headers['content-type']).to eq('application/json')
    end
  end

  describe 'expiry' do
    before { allow(Familia).to receive(:now).and_return(now + Onetime::SessionImpersonation::TTL + 1) }

    it 'ends the impersonation, audits it, and lets the request through unguarded' do
      env    = env_for('POST', '/api/v3', '/secret/conceal')
      status, = middleware.call(env)

      expect(status).to eq(200)
      expect(impersonating_session).not_to have_key(Onetime::SessionImpersonation::SESSION_KEY)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'customer.impersonate.stop', detail: hash_including(ended_by: 'expired')),
      )
    end

    it 'publishes no context for the expired marker' do
      middleware.call(env_for('GET', '', '/dashboard'))

      expect(observed[:context]).to be_nil
    end
  end

  # The frontend's error classifier (src/schemas/errors/classifier.ts
  # #extractUserMessage) toasts `details.error` verbatim, so `error` has to be
  # the sentence and the machine token has to live somewhere else.
  describe 'the 403 wire contract' do
    subject(:parsed) do
      _status, _headers, body = middleware.call(env_for('POST', '/api/v3', '/secret/conceal'))
      JSON.parse(body.first)
    end

    it 'puts a human sentence in `error`' do
      expect(parsed['error'])
        .to eq('This session is impersonating a customer and is read-only. ' \
               'Stop impersonating to make changes.')
    end

    it 'puts the machine token in `error_code`' do
      expect(parsed['error_code']).to eq('impersonation_read_only')
    end

    it 'never puts the token where the classifier would toast it' do
      expect(parsed['error']).not_to eq(described_class::ERROR_CODE)
    end

    it 'carries exactly the two keys' do
      expect(parsed.keys).to contain_exactly('error', 'error_code')
    end
  end

  describe 'the per-request target memo' do
    let(:target) { instance_double(Onetime::Customer, extid: 'ur_target', exists?: true) }

    before { allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(target) }

    it 'loads the target once and parks it in env for the identity call sites' do
      env = env_for('GET', '', '/dashboard')

      middleware.call(env)

      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).once.with('ur_target')
      expect(env[Onetime::SessionImpersonation::TARGET_ENV_KEY]).to eq(['ur_target', target])
    end

    # This is the point of the memo: resolve() reads the target twice on its
    # own, and up to three call sites call resolve per request.
    it 'serves every downstream resolve from the same single load' do
      env = env_for('GET', '', '/dashboard')
      middleware.call(env)

      principal = instance_double(Onetime::Customer, extid: 'ur_colonel', verified?: true)
      allow(principal).to receive(:role?).with('colonel').and_return(true)
      allow(target).to receive(:suspended?).and_return(false)
      allow(target).to receive(:role?).with('colonel').and_return(false)

      3.times do
        effective, = Onetime::SessionImpersonation.resolve(impersonating_session, principal, env: env)
        expect(effective).to be(target)
      end

      expect(Onetime::Customer).to have_received(:load_by_extid_or_email).once
    end

    it 'primes nothing for an ordinary session' do
      env = env_for('GET', '', '/dashboard', session: { 'external_id' => 'ur_alice' })

      middleware.call(env)

      expect(env).not_to have_key(Onetime::SessionImpersonation::TARGET_ENV_KEY)
    end
  end

  describe 'the stop path constant' do
    # Duplicated in src/services/impersonation.service.ts and declared in
    # apps/api/v2/routes.txt; a silent rename makes the stop button unusable
    # from inside the state it ends.
    it 'is the Account API route' do
      expect(described_class::STOP_PATH).to eq('/api/account/impersonation/stop')
    end

    it 'is not under a blocked prefix' do
      expect(described_class::BLOCKED_PREFIXES).to(
        all(satisfy { |prefix| !described_class::STOP_PATH.start_with?("#{prefix}/") }),
      )
    end
  end
end
