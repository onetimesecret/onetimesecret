# apps/web/auth/spec/integration/full/public_host_fallback_spec.rb
#
# frozen_string_literal: true

# H-05: without an allowlisted origin, neither URL consumer may use Rack's
# authority. Reset requests must refuse before account lookup/key writes, not
# merely roll back a key after email construction fails.
# Run: tests/lanes/run full-pg-agnostic --only apps/web/auth/spec/integration/full/public_host_fallback_spec.rb
require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'
require_relative '../../../lib/public_host'
require 'stringio'

# rubocop:disable-next RSpec/SpecFilePathFormat -- full-mode lane owns this integration directory
RSpec.describe Auth::PublicHost, :aggregate_failures, :shared_db_state, type: :integration do
  include Rack::Test::Methods

  include_context 'domains enabled'
  include_context 'tenant fixtures'

  let(:site_host) { nil }
  let(:delivered) { [] }
  let(:sql_log) { StringIO.new }

  around do |example|
    saved_host = OT.conf['site']['host']
    sql_logger = Logger.new(sql_log)
    begin
      auth_db.loggers << sql_logger
      OT.conf['site']['host'] = site_host
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
      example.run
    ensure
      auth_db.loggers.delete(sql_logger)
      OT.conf['site']['host'] = saved_host
      Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
    end
  end

  before do
    Onetime::Application::MiddlewareStack.ip_privacy_security_config
    Onetime::CustomDomain::SigninConfig.create!(
      domain_id: test_custom_domain.identifier,
      enabled: true,
      signin_enabled: true,
    )
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email_raw) do |email, **_kwargs|
      delivered << email
      true
    end
  end

  after do
    Onetime::CustomDomain::SigninConfig.delete_for_domain!(test_custom_domain.identifier)
    clear_auth_database
  end

  def resolver
    Auth::Config::Features::OmniAuth
  end

  def candidate_env(host = nil)
    env                           = Rack::MockRequest.env_for('https://unregistered.tenant-example.com/auth')
    env['onetime.display_domain'] = host unless host.nil?
    env
  end

  def expect_origin(env, origin)
    expect(Auth::Router.new(env).rodauth.base_url).to eq(origin)
    expect(resolver.full_host_for(env)).to eq(origin)
  end

  def expect_refused_origin(env)
    # Keep the optional helpers' nil contract; only credential URL consumers
    # require the origin and raise the typed configuration failure.
    expect(described_class.allowlisted_base_url(env)).to be_nil
    expect(described_class.allowlisted_host(env)).to be_nil
    [-> { Auth::Router.new(env).rodauth.base_url }, -> { resolver.full_host_for(env) }].each do |consumer|
      expect(&consumer).to raise_error(StandardError, /No allowlisted auth origin/) do |error|
        expect(error.class.name).to eq('Auth::PublicHost::MissingAllowlistedOrigin')
      end
    end
  end

  it 'refuses both consumers when host middleware has not supplied a candidate' do
    expect_refused_origin(candidate_env)
  end

  it 'refuses an unregistered display host' do
    expect_refused_origin(candidate_env('unregistered.tenant-example.com'))
  end

  it 'refuses a registered but unverified display host' do
    test_custom_domain.verified = false
    test_custom_domain.save
    expect_refused_origin(candidate_env(tenant_domain))
  end

  it 'refuses an unreadable tenant without substituting the raw Host' do
    allow(Onetime::CustomDomain).to receive(:display_domain_id_for)
      .and_raise(Redis::BaseError.new('simulated read failure'))
    expect_refused_origin(candidate_env(tenant_domain))
  end

  it 'does not trust a raw Host or forwarded authority even when it names a canonical host' do
    env                          = candidate_env
    env['HTTP_HOST']             = canonical_host
    env['HTTP_X_FORWARDED_HOST'] = canonical_host
    expect_refused_origin(env)
  end

  it 'requires recipient authorization for credential URLs without site.host' do
    env = candidate_env(tenant_domain)
    expect { Auth::Router.new(env).rodauth.base_url }
      .to raise_error(described_class::MissingAllowlistedOrigin)
    expect(resolver.full_host_for(env)).to eq("https://#{tenant_domain}")
  end

  it 'retains a configured canonical candidate without site.host' do
    expect_origin(candidate_env(canonical_host), "https://#{canonical_host}")
  end

  context 'with a blank site.host' do
    let(:site_host) { '' }

    it 'refuses instead of reading the request authority' do
      expect_refused_origin(candidate_env)
    end
  end

  context 'with a configured site.host' do
    let(:site_host) { 'operator.example.org:8443' }

    it 'retains the request-independent canonical fallback' do
      expect_origin(candidate_env('unregistered.tenant-example.com'), 'https://operator.example.org:8443')
    end

    it 'uses canonical credentials while retaining the tenant SSO origin' do
      env = candidate_env(tenant_domain)
      expect(Auth::Router.new(env).rodauth.base_url).to eq('https://operator.example.org:8443')
      expect(resolver.full_host_for(env)).to eq("https://#{tenant_domain}")
    end
  end

  describe 'reset request preflight' do
    let(:account_email) { unique_test_email('missing-origin') }
    let!(:account_id) { seed_account_with_password(account_email) }

    before do
      test_custom_domain.verified = false
      test_custom_domain.save
      header 'Host', tenant_domain
      header 'X-Forwarded-Proto', 'https'
      header 'X-Request-Id', 'h05-reset-preflight'
    end

    def request_reset(login)
      clear_sql_log
      clear_cookies
      csrf_json_post('/auth/reset-password-request', login: login)
      expect(last_request.env['HTTP_X_CSRF_TOKEN']).not_to be_nil
      [last_response.status, JSON.parse(last_response.body)]
    end

    def with_reset_limiter(enabled:, max_per_ip: 2)
      authentication = OT.conf['site']['authentication']
      saved          = authentication['reset_request_rate_limit']
      redis          = Onetime::Customer.dbclient
      begin
        authentication['reset_request_rate_limit'] = {
          'enabled' => enabled,
          'max_per_ip' => max_per_ip,
          'max_per_email' => 100,
          'window' => 900,
          'lockout' => 900,
        }
        keys                                       = redis.keys('reset_request:attempts:*') + redis.keys('reset_request:locked:*')
        redis.del(*keys) unless keys.empty?
        yield redis
      ensure
        authentication['reset_request_rate_limit'] = saved
        keys                                       = redis.keys('reset_request:attempts:*') + redis.keys('reset_request:locked:*')
        redis.del(*keys) unless keys.empty?
      end
    end

    def clear_sql_log
      sql_log.truncate(0)
      sql_log.rewind
    end

    def expect_no_reset_work
      expect(sql_log.string).not_to match(/\bSELECT\b[^\n]*\bFROM\s+["`]?accounts\b/i)
      expect(sql_log.string).not_to match(/INSERT INTO ["`]?account_password_reset_keys/i)
      expect(delivered).to be_empty
      expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)
    end

    it 'counts an enabled limiter before resolving the missing origin' do
      with_reset_limiter(enabled: true) do |redis|
        counts_at_resolution = []
        allow(described_class).to receive(:required_base_url!).and_wrap_original do |original, env|
          counts_at_resolution << redis.get("reset_request:attempts:email:#{account_email}") if env['REQUEST_METHOD'] == 'POST'
          original.call(env)
        end

        expect(request_reset(account_email).first).to eq(500)
        expect(counts_at_resolution).to eq(['1'])
        expect_no_reset_work
      end
    end

    it 'returns 429 before origin resolution or account lookup when the limiter is locked' do
      with_reset_limiter(enabled: true, max_per_ip: 1) do
        expect(request_reset(account_email).first).to eq(500)
        allow(described_class).to receive(:required_base_url!).and_call_original
        clear_sql_log

        status, body = request_reset(account_email)
        expect(status).to eq(429)
        expect(body).to include('error_type' => 'LimitExceeded')
        expect(described_class).not_to have_received(:required_base_url!)
        expect_no_reset_work
      end
    end

    it 'requires an origin even when the limiter is explicitly disabled' do
      with_reset_limiter(enabled: false) do |redis|
        clear_sql_log

        expect(request_reset(account_email).first).to eq(500)
        expect(redis.keys('reset_request:attempts:*')).to be_empty
        expect_no_reset_work
      end
    end

    it 'refuses without an account SELECT, INSERT, email, or persisted reset key' do
      sql_log.truncate(0)
      sql_log.rewind
      status, body = request_reset(account_email)

      expect(status).to eq(500)
      expect(body).to include('error' => 'Internal Server Error', 'error_type' => 'ServerError')
      expect(sql_log.string).not_to match(/\bSELECT\b[^\n]*\bFROM\s+["`]?accounts\b/i)
      expect(sql_log.string).not_to match(/INSERT INTO ["`]?account_password_reset_keys/i)
      expect(delivered).to be_empty
      expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)
    end

    it 'also refuses direct reset-key creation before the database write' do
      auth = Auth::Router.new(candidate_env(tenant_domain)).rodauth
      auth.instance_variable_set(:@account, auth_db[:accounts].where(id: account_id).first)
      auth.instance_variable_set(:@reset_password_key_value, 'proposed-reset-key')
      sql_log.truncate(0)
      sql_log.rewind

      expect { auth.create_reset_password_key }.to raise_error(described_class::MissingAllowlistedOrigin)
      expect(sql_log.string).not_to match(/INSERT INTO ["`]?account_password_reset_keys/i)
      expect(auth_db[:account_password_reset_keys].where(id: account_id).count).to eq(0)
    end

    it 'gives the same refusal for existing and missing accounts' do
      expect(request_reset(account_email)).to eq(request_reset(unique_test_email('missing')))
      expect(delivered).to be_empty
    end

    it 'gives the same refusal for unopen and missing accounts' do
      auth_db[:accounts].where(id: account_id).update(status_id: AuthTestConstants::STATUS_UNVERIFIED)
      expect(request_reset(account_email)).to eq(request_reset(unique_test_email('missing-unopen')))
      expect(delivered).to be_empty
    end

    it 'does not let a resend-throttled account bypass the origin refusal' do
      auth_db[:account_password_reset_keys].insert(
        id: account_id,
        key: 'recent-reset-key',
        deadline: Time.now + 3600,
        email_last_sent: Time.now,
      )

      response = request_reset(account_email)
      expect(response.first).to eq(500)
      expect(response).to eq(request_reset(unique_test_email('missing-throttled')))
      expect(delivered).to be_empty
    end

    it 'does not update an existing reset key or its resend timestamp' do
      auth_db[:account_password_reset_keys].insert(
        id: account_id,
        key: 'existing-reset-key',
        deadline: Time.now + 3600,
        email_last_sent: Time.now - 600,
      )
      original = auth_db[:account_password_reset_keys].where(id: account_id).first

      expect(request_reset(account_email).first).to eq(500)
      expect(auth_db[:account_password_reset_keys].where(id: account_id).first).to eq(original)
      expect(delivered).to be_empty
    end
  end
end
