# frozen_string_literal: true

require_relative '../integration_spec_helper'
require 'base64'

# Current route/strategy behavior, not a proposed Bearer authentication policy.
# HTTP-01/05: mounted middleware, authentication and persistence remain real.
RSpec.describe 'V3 current authentication boundaries in simple mode', type: :integration do
  include_context 'auth_rack_test'

  let(:app) do
    @authentication_boundary_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  let(:password) { 'Authentication-Boundary1234!' }
  let(:credential_customer) { create_customer }
  let(:payload) { { secret: { secret: 'authentication boundary fixture', ttl: 3600 } } }

  before(:all) { Onetime.boot! :test }

  around do |example|
    api_config = OT.conf.fetch('site').fetch('interface').fetch('api')
    original_guest_routes = api_config.fetch('guest_routes')
    begin
      api_config['guest_routes'] = original_guest_routes.merge('enabled' => true, 'conceal' => true)
      example.run
    ensure
      api_config['guest_routes'] = original_guest_routes
    end
  end

  before do
    clear_cookies
    %w[Authorization Content-Type Accept X-CSRF-Token Origin].each { |name| header name, nil }
    # No authentication, resolver, entitlement or datastore mocks.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
  end

  def create_customer(with_password: false)
    customer = Onetime::Customer.new(email: "authentication-boundary-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase(password) if with_password
    customer.verified = 'true'
    customer.apitoken = SecureRandom.hex(20)
    customer.save
    customer
  end

  def sign_in!
    customer = create_customer(with_password: true)
    post_json '/auth/login', { login: customer.email, password: password }
    expect(last_response.status).to eq(200)
    customer
  end

  def authorization(kind)
    case kind
    when :basic
      "Basic #{Base64.strict_encode64("#{credential_customer.email}:#{credential_customer.apitoken}")}"
    when :invalid_basic
      "Basic #{Base64.strict_encode64("#{credential_customer.email}:wrong-api-key")}"
    when :bearer
      'Bearer unimplemented-authentication-boundary-token'
    end
  end

  def post_creation(path, authorization: nil, csrf_token: nil)
    env = { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
    env['HTTP_AUTHORIZATION'] = authorization if authorization
    env['HTTP_X_CSRF_TOKEN'] = csrf_token if csrf_token
    post path, payload.to_json, env
  end

  def fresh_csrf_token
    header 'Content-Type', nil
    token = fetch_csrf_token
    expect(token).to be_a(String)
    expect(token).not_to be_empty
    token
  end

  def secret_storage
    [Onetime::Secret, Onetime::Receipt].to_h do |model|
      keys = model.dbclient.scan_each(match: "#{model.prefix}:*").to_a.sort
      [model.name, keys.to_h { |key| [key, model.dbclient.dump(key)] }]
    end
  end

  def expect_session_refusal(code = 'not_authenticated')
    expect(last_response.status).to eq(401)
    expect(json_response).to include('code' => code, 'code_scope' => 'customer_session')
    expect(last_response.headers['www-authenticate']).to eq('Session realm="onetimesecret"')
  end

  def expect_created_pair(owner_id:, source: 'standard')
    expect(last_response.status).to eq(200)
    record = json_response.fetch('record')
    receipt = Onetime::Receipt.load(record.fetch('receipt').fetch('identifier'))
    secret = Onetime::Secret.load(record.fetch('secret').fetch('identifier'))
    expect(receipt).not_to be_nil
    expect(secret).not_to be_nil
    expect(receipt).to have_attributes(owner_id: owner_id, source: source, secret_identifier: secret.identifier)
    expect(secret).to have_attributes(owner_id: owner_id, receipt_identifier: receipt.identifier)
  end

  def use_cookie(value)
    clear_cookies
    set_cookie "#{Onetime.session_config.fetch('key')}=#{value}"
  end

  shared_examples 'header-only anonymous creation' do |path, owner_id, source|
    %i[none basic invalid_basic bearer].each do |kind|
      it "keeps #{kind} header-only creation anonymous" do
        post_creation path, authorization: authorization(kind)

        expect_created_pair(owner_id: owner_id, source: source)
        result = last_request.env.fetch('otto.strategy_result')
        expect(result.auth_method).to eq('noauth')
        expect(result.user).to be_nil
      end
    end

    it 'treats an unknown session cookie as anonymous rather than as the header owner' do
      use_cookie(SecureRandom.hex(32))
      post_creation path, authorization: authorization(:basic)

      expect_created_pair(owner_id: owner_id, source: source)
      expect(last_request.env.fetch('otto.strategy_result').user).to be_nil
    end
  end

  shared_examples 'session-owned creation with CSRF' do |path, auth_method, source|
    %i[basic bearer].each do |kind|
      it "requires CSRF and retains the session owner despite #{kind}" do
        customer = sign_in!
        token = fresh_csrf_token
        presented_header = authorization(kind)
        before_storage = secret_storage

        [nil, 'invalid-csrf-token'].each do |invalid_token|
          post_creation path, authorization: presented_header, csrf_token: invalid_token
          expect(last_response.status).to eq(403)
          expect(last_request.env['onetime.csrf.rejected']).to be(true)
          expect(secret_storage).to eq(before_storage)
        end

        post_creation path, authorization: presented_header, csrf_token: token
        expect_created_pair(owner_id: customer.objid, source: source)
        result = last_request.env.fetch('otto.strategy_result')
        expect(result.auth_method).to eq(auth_method)
        expect(result.user.objid).to eq(customer.objid)
      end
    end
  end

  describe 'HTTP-01.R1: normal session-only operations' do
    %i[none basic invalid_basic bearer].each do |kind|
      it "refuses #{kind} without a session on reads and both creation routes" do
        presented_header = authorization(kind)
        env = { 'HTTP_ACCEPT' => 'application/json' }
        env['HTTP_AUTHORIZATION'] = presented_header if presented_header
        before_storage = secret_storage

        get '/api/v3/receipt/recent', {}, env
        expect_session_refusal
        expect(secret_storage).to eq(before_storage)

        %w[conceal generate].each do |operation|
          post_creation "/api/v3/secret/#{operation}", authorization: presented_header
          expect_session_refusal
          expect(secret_storage).to eq(before_storage)
        end
      end
    end

    %w[malformed unknown].each do |cookie_kind|
      it "does not create protected records with a #{cookie_kind} cookie and valid Basic credentials" do
        cookie = cookie_kind == 'malformed' ? 'not-a-session-id' : SecureRandom.hex(32)
        presented_header = authorization(:basic)
        before_storage = secret_storage
        use_cookie(cookie)
        get '/api/v3/receipt/recent', {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => presented_header }
        expect_session_refusal

        use_cookie(cookie)
        post_creation '/api/v3/secret/conceal', authorization: presented_header
        expect_session_refusal
        expect(secret_storage).to eq(before_storage)
      end
    end

    it 'accepts the same real Basic credentials only on the explicit version control route' do
      get '/api/v3/version', {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => authorization(:basic) }

      expect(last_response.status).to eq(200)
      result = last_request.env.fetch('otto.strategy_result')
      expect(result.auth_method).to eq('basic_auth')
      expect(result.user.objid).to eq(credential_customer.objid)
    end

    include_examples 'session-owned creation with CSRF', '/api/v3/secret/conceal', 'sessionauth', 'standard'
  end

  describe 'HTTP-01.R3/HTTP-05.R4: noauth guest creation' do
    include_examples 'header-only anonymous creation', '/api/v3/guest/secret/conceal', nil, 'standard'
    include_examples 'session-owned creation with CSRF', '/api/v3/guest/secret/conceal', 'noauth', 'standard'

    it 'does not let valid header-only credentials bypass disabled guest conceal' do
      OT.conf['site']['interface']['api']['guest_routes']['conceal'] = false
      before_storage = secret_storage
      post_creation '/api/v3/guest/secret/conceal', authorization: authorization(:basic)

      expect(last_response.status).to eq(403)
      expect(json_response).to include('code' => 'GUEST_CONCEAL_DISABLED')
      expect(last_request.env['onetime.csrf.rejected']).to be_nil
      expect(secret_storage).to eq(before_storage)
    end
  end

  describe 'HTTP-05.R1: ended or rejected sessions' do
    it 'refuses a replayed logged-out cookie on protected creation but permits anonymous guest creation' do
      sign_in!
      old_cookie = rack_mock_session.cookie_jar[Onetime.session_config.fetch('key')]
      expect(old_cookie).to be_a(String)
      get '/logout', {}, { 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200)

      use_cookie(old_cookie)
      before_storage = secret_storage
      post_creation '/api/v3/secret/conceal', authorization: authorization(:basic)
      expect_session_refusal
      expect(secret_storage).to eq(before_storage)

      use_cookie(old_cookie)
      post_creation '/api/v3/guest/secret/conceal', authorization: authorization(:basic)
      expect_created_pair(owner_id: nil)
      expect(last_request.env.fetch('otto.strategy_result').user).to be_nil
    end

    it 'withholds a suspended identity while retaining raw-session CSRF checks and anonymous guest behavior' do
      customer = sign_in!
      token = fresh_csrf_token
      customer.suspended!('true')
      presented_header = authorization(:basic)
      before_storage = secret_storage

      post_creation '/api/v3/secret/conceal', authorization: presented_header, csrf_token: token
      expect_session_refusal('account_suspended')
      expect(secret_storage).to eq(before_storage)

      post_creation '/api/v3/guest/secret/conceal', authorization: presented_header
      expect(last_response.status).to eq(403)
      expect(last_request.env['onetime.csrf.rejected']).to be(true)
      expect(secret_storage).to eq(before_storage)

      post_creation '/api/v3/guest/secret/conceal', authorization: presented_header, csrf_token: token
      expect_created_pair(owner_id: nil)
      expect(last_request.env.fetch('otto.strategy_result').user).to be_nil
    end
  end

  describe 'HTTP-01.R3/HTTP-05.R4: Incoming creation' do
    around do |example|
      original_config = OT.conf.fetch('features').fetch('incoming')
      original_public = OT.incoming_public_recipients
      original_lookup = OT.incoming_recipient_lookup
      begin
        OT.conf['features']['incoming'] = original_config.merge(
          'enabled' => true,
          'recipients' => [{ 'email' => 'authentication-incoming@example.com', 'name' => 'Auth boundary' }],
        )
        Onetime::Initializers::SetupIncomingRecipients.new.execute(nil)
        example.run
      ensure
        OT.conf['features']['incoming'] = original_config
        OT.instance_variable_set(:@incoming_public_recipients, original_public)
        OT.instance_variable_set(:@incoming_recipient_lookup, original_lookup)
      end
    end

    let(:payload) do
      { secret: { secret: 'incoming authentication fixture', memo: 'auth boundary',
                  recipient: OT.incoming_public_recipients.fetch(0).fetch('digest') } }
    end

    include_examples 'header-only anonymous creation', '/api/incoming/secret', 'anon', 'incoming'
    include_examples 'session-owned creation with CSRF', '/api/incoming/secret', 'noauth', 'incoming'
  end
end
