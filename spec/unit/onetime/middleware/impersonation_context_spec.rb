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

  # What Rack::Parser (mounted ABOVE this guard) leaves behind for ANY method
  # whose Content-Type matches: a parsed body in form_hash, which
  # Rack::Request#POST then returns even on a GET.
  def with_json_body(env, payload)
    input = StringIO.new(JSON.generate(payload))
    env.merge(
      'CONTENT_TYPE' => 'application/json',
      'rack.input' => input,
      'rack.request.form_input' => input,
      'rack.request.form_hash' => payload,
    )
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

    it 'allows HEAD' do
      status, = middleware.call(env_for('HEAD', '', '/dashboard'))

      expect(status).to eq(200)
    end

    # Otto dispatches OPTIONS rows to real handlers — `OPTIONS /secret/generate`
    # runs GenerateSecret and CREATES a secret. A CORS preflight carries no
    # cookies, so no legitimate impersonated request is an OPTIONS.
    it 'denies OPTIONS, which Otto routes to real handlers' do
      status, = middleware.call(env_for('OPTIONS', '/api/v2', '/secret/generate'))

      expect(status).to eq(403)
      expect(observed[:called]).to be_nil
    end

    it 'denies OPTIONS even on an ordinary path' do
      expect(middleware.call(env_for('OPTIONS', '', '/dashboard')).first).to eq(403)
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

    # GET /api/v{2,3}/secret/:id CONSUMES the secret when the request carries
    # continue=true, so the PATH is denied — no param sniffing involved.
    describe 'consuming secret reads' do
      %w[/api/v2 /api/v3].each do |mount|
        it "denies GET #{mount}/secret/:id" do
          status, _headers, body = middleware.call(env_for('GET', mount, '/secret/abc123'))

          expect(status).to eq(403)
          expect(json_error(body)['error_code']).to eq('impersonation_read_only')
        end

        it "denies the guest twin under #{mount}" do
          expect(middleware.call(env_for('GET', mount, '/guest/secret/abc123')).first).to eq(403)
        end

        # #3633 made the status endpoint a pure read; it must stay reachable.
        it "allows GET #{mount}/secret/:id/status" do
          expect(middleware.call(env_for('GET', mount, '/secret/abc123/status')).first).to eq(200)
        end

        it "allows the receipt reads under #{mount}" do
          expect(middleware.call(env_for('GET', mount, '/receipt/abc123')).first).to eq(200)
          expect(middleware.call(env_for('GET', mount, '/receipt/recent')).first).to eq(200)
        end
      end

      it 'denies HEAD on a consuming secret read too' do
        expect(middleware.call(env_for('HEAD', '/api/v2', '/secret/abc123')).first).to eq(403)
      end

      # v1's reveal is a POST, so its GETs are ordinary receipt reads.
      it 'leaves the v1 receipt reads alone' do
        expect(middleware.call(env_for('GET', '/api/v1', '/receipt/abc123')).first).to eq(200)
      end
    end

    # The bypass this guard shipped with: Rack::Parser publishes a JSON body
    # as form_hash for ANY method, so `continue` never had to be in the query
    # string. Path denial closes it; this proves the closure.
    describe 'reveal intent smuggled in a JSON body on a GET' do
      it 'denies it on the consuming secret path' do
        env = with_json_body(env_for('GET', '/api/v3', '/secret/abc123'), 'continue' => true)

        status, _headers, body = middleware.call(env)

        expect(status).to eq(403)
        expect(json_error(body)['error_code']).to eq('impersonation_read_only')
        expect(observed[:called]).to be_nil
      end

      # Belt-and-braces: a reveal-intent param on a path the deny list does not
      # know about is still refused, whichever side it arrives on.
      it 'denies it on an unlisted path via the body' do
        env = with_json_body(env_for('GET', '', '/some/future/reveal'), 'continue' => true)

        expect(middleware.call(env).first).to eq(403)
      end

      it 'denies it on an unlisted path via the query string' do
        env = env_for('GET', '', '/some/future/reveal', 'QUERY_STRING' => 'continue=true')

        expect(middleware.call(env).first).to eq(403)
      end

      it 'allows an unlisted path whose body does not ask for a reveal' do
        env = with_json_body(env_for('GET', '', '/some/future/reveal'), 'continue' => false)

        expect(middleware.call(env).first).to eq(200)
      end
    end

    describe 'GETs that mint external artifacts' do
      {
        'the Stripe customer portal (also creates a default org)' => ['', '/billing/portal'],
        'the legacy customer-portal redirect' => ['', '/account/billing_portal'],
        'the post-checkout finalizer' => ['', '/billing/welcome'],
        'the checkout entry point' => ['', '/billing/plans/identity/monthly'],
        'the legacy tier redirect' => ['', '/plans/identity'],
        'the legacy tier+cycle redirect' => ['', '/plans/identity/month'],
        'the DNS widget token' => ['/api/domains', '/dns-widget/token'],
        'the plan-intent consumer' => ['/billing', '/api/org/org_abc/subscription'],
      }.each do |what, (script_name, path_info)|
        it "denies #{what}" do
          status, _headers, body = middleware.call(env_for('GET', script_name, path_info))

          expect(status).to eq(403), "#{script_name}#{path_info} was allowed"
          expect(json_error(body)['error_code']).to eq('impersonation_read_only')
        end
      end

      # The pages and reads that sit next to them must stay reachable, or the
      # operator cannot see what they came to look at.
      {
        'the billing plans page itself' => ['/billing', '/plans'],
        'the billing overview page' => ['/billing', '/overview'],
        'the org billing overview read' => ['/billing', '/api/org/org_abc'],
        'the invoices read' => ['/billing', '/api/org/org_abc/invoices'],
        'the public plan catalogue' => ['/billing', '/api/plans'],
        'the pricing page' => ['', '/pricing'],
        'the account page' => ['', '/account'],
        'the account settings page' => ['', '/account/settings'],
        'the domains list' => ['/api/domains', '/'],
        'a single domain read' => ['/api/domains', '/dom_abc'],
      }.each do |what, (script_name, path_info)|
        it "allows #{what}" do
          status, = middleware.call(env_for('GET', script_name, path_info))

          expect(status).to eq(200), "#{script_name}#{path_info} was denied"
        end
      end
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
  # An earlier version returned '/' from request_path on failure, which is on
  # no deny list — so an unparseable path was served as an ordinary page read.
  describe 'unparseable paths fail CLOSED' do
    before do
      allow(Otto::Utils).to receive(:normalize_path).and_raise(ArgumentError, 'bad path')
      allow(OT).to receive(:le)
    end

    it 'denies a read it cannot name' do
      status, _headers, body = middleware.call(env_for('GET', '', '/dashboard'))

      expect(status).to eq(403)
      expect(json_error(body)['error_code']).to eq('impersonation_read_only')
      expect(observed[:called]).to be_nil
    end

    it 'answers JSON rather than raising inside the denial' do
      env = env_for('GET', '', '/dashboard', 'HTTP_ACCEPT' => 'text/html')

      status, headers, = middleware.call(env)

      expect(status).to eq(403)
      expect(headers['content-type']).to eq('application/json')
    end

    it 'says so in the log' do
      middleware.call(env_for('GET', '', '/dashboard'))

      expect(OT).to have_received(:le).with(/path normalization failed/)
    end
  end

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
