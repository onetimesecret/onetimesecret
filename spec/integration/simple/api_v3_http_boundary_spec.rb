# frozen_string_literal: true

require_relative '../integration_spec_helper'
require 'base64'

# Boot the mounted applications once; each example's datastore is isolated by
# the integration hooks. Keep each request and its storage/control assertions together.
# rubocop:disable-next RSpec/DescribeClass, RSpec/BeforeAfterAll, RSpec/InstanceVariable, RSpec/ExampleLength
RSpec.describe 'V2/V3 HTTP method and parser boundaries', :aggregate_failures, type: :integration do
  include_context 'auth_rack_test'

  before(:all) do
    Onetime.boot! :test
    Onetime::Application::Registry.reset!
    Onetime::Application::Registry.prepare_application_registry
    @http_boundary_app     = Onetime::Application::Registry.generate_rack_url_map
    # Otto skips its production lazy freeze under RSpec. Exercise that state
    # explicitly, including both literal and dynamic HEAD dispatch.
    @http_boundary_routers = [V2::Application, V3::Application, Incoming::Application].to_h do |application|
      router = Onetime::Application::Registry.application_instances.fetch(application).router
      router.freeze_configuration!
      [application.uri_prefix, router]
    end
  end

  let(:app) { @http_boundary_app }

  before do
    clear_cookies
    %w[Authorization Content-Type Accept X-CSRF-Token Origin].each { |name| header name, nil }
    @guest_policy   = Marshal.load(Marshal.dump(OT.conf['site']['interface']['api']['guest_routes']))
    @creation_limit = Marshal.load(Marshal.dump(OT.conf['site']['secret_options']['create_rate_limit']))
  end

  after do
    OT.conf['site']['interface']['api']['guest_routes'].replace(@guest_policy)
    OT.conf['site']['secret_options']['create_rate_limit'] = @creation_limit
  end

  def anonymous_post(path, payload = {}, env = {})
    post path, JSON.generate(payload), { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }.merge(env)
  end

  def create_pair(version: 'v3', kind: 'conceal')
    anonymous_post "/api/#{version}/guest/secret/#{kind}", { secret: { secret: 'http boundary content', ttl: 3600 } }
    expect(last_response.status).to eq(200), last_response.body
    record = json_response.fetch('record')
    [record.fetch('receipt').fetch('identifier'), record.fetch('secret').fetch('identifier')]
  end

  def sign_in!
    customer          = Onetime::Customer.new(email: "http-boundary-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase('HTTP-Boundary123!')
    customer.verified = 'true'
    customer.save
    post_json '/auth/login', { login: customer.email, password: 'HTTP-Boundary123!' }
    expect(last_response.status).to eq(200), last_response.body
    customer
  end

  # Compare storage, not just response handles: an empty response could hide a write.
  def secret_storage
    [Onetime::Secret, Onetime::Receipt].to_h do |model|
      keys = model.dbclient.scan_each(match: "#{model.prefix}:*").to_a.sort
      [model.name, keys.to_h { |key| [key, model.dbclient.dump(key)] }]
    end
  end

  def raw_response(path, query: '', method: 'GET', body: nil, content_type: nil)
    env                            = Rack::MockRequest.env_for(path, method: method, input: body.to_s)
    env['QUERY_STRING']            = query
    if content_type
      env['CONTENT_TYPE'] = content_type
    else
      env.delete('CONTENT_TYPE')
    end
    status, headers, response_body = app.call(env)
    chunks                         = []
    # Rack bodies require #each, not Enumerable#map.
    # rubocop:disable-next Style/MapIntoArray
    response_body.each { |chunk| chunks << chunk }
    [status, headers, chunks.join]
  ensure
    response_body.close if response_body.respond_to?(:close)
  end

  def expect_parser_error(response)
    status, headers, body = response
    expect(status).to eq(400)
    expect(headers['content-type']).to eq('application/json')
    expect(headers['cache-control']).to eq('private, no-store')
    expect(headers['x-request-id']).not_to be_nil
    expect(JSON.parse(body)).to include('message' => a_kind_of(String))
    expect(body).not_to include('sensitive-query', 'sensitive-body')
  end

  describe 'HTTP-02/03/10: narrow client parser errors' do
    %w[/api/v2/status /api/v3/status /api/incoming/config].each do |path|
      %w[x=one&x[]=two x=%ZZ].each do |query|
        it "returns a controlled 400 for #{path} with #{query}" do
          before_storage = secret_storage
          response       = raw_response(path, query: "#{query}&sensitive-query=hidden")
          expect(secret_storage).to eq(before_storage)
          expect_parser_error(response)
        end
      end
    end

    %w[/api/v2/guest/secret/generate /api/v3/guest/secret/generate /api/incoming/secret].each do |path|
      it "rejects malformed JSON without writes at #{path}" do
        before_storage = secret_storage
        response       = raw_response(path, method: 'POST', body: '{"sensitive-body":', content_type: 'application/json')
        expect(secret_storage).to eq(before_storage)
        expect_parser_error(response)
      end

      it "rejects malformed form encoding without writes at #{path}" do
        before_storage = secret_storage
        response       = raw_response(path, method: 'POST', body: 'x=one&x[]=two&sensitive-body=hidden', content_type: 'application/x-www-form-urlencoded')
        expect(secret_storage).to eq(before_storage)
        expect_parser_error(response)
      end

      it "rejects malformed implicit form encoding without Content-Type or writes at #{path}" do
        before_storage = secret_storage
        response = raw_response(path, method: 'POST', body: '%ZZ')
        expect(secret_storage).to eq(before_storage)
        expect_parser_error(response)
        expect(JSON.parse(response.last)).to eq('message' => 'Invalid form parameters')
      end

      it "keeps malformed multipart a client error at #{path}" do
        before_storage = secret_storage
        response       = raw_response(path, method: 'POST', body: 'sensitive-body', content_type: 'multipart/form-data')
        expect(secret_storage).to eq(before_storage)
        expect_parser_error(response)
      end
    end

    it 'suppresses the body even on an early HEAD parser refusal' do
      status, headers, body = raw_response('/api/v3/status', method: 'HEAD', query: 'x=%ZZ')
      expect(status).to eq(400)
      expect(headers['cache-control']).to eq('private, no-store')
      expect(body).to eq('')
    end

    it 'preserves JSON body precedence over query parameters' do
      anonymous_post '/api/v3/guest/secret/conceal?secret[secret]=query', { secret: { secret: 'body', ttl: 3600 } }
      expect(last_response.status).to eq(200), last_response.body
      identifier = json_response.dig('record', 'secret', 'identifier')
      expect(Onetime::Secret.load(identifier).decrypted_secret_value).to eq('body')
    end

    it 'preserves form body precedence over query parameters' do
      post '/api/v3/guest/secret/conceal?secret[secret]=query',
        'secret[secret]=body&secret[ttl]=3600',
        { 'CONTENT_TYPE' => 'application/x-www-form-urlencoded', 'HTTP_ACCEPT' => 'application/json' }
      expect(last_response.status).to eq(200), last_response.body
      identifier = json_response.dig('record', 'secret', 'identifier')
      expect(Onetime::Secret.load(identifier).decrypted_secret_value).to eq('body')
    end

    it 'preserves current scalar generation coercion rather than deciding a new body contract' do
      anonymous_post '/api/v3/guest/secret/generate', false
      expect(last_response.status).to eq(200), last_response.body
      expect(Onetime::Secret.load(json_response.dig('record', 'secret', 'identifier'))).not_to be_nil
    end
  end

  describe 'HTTP-04/08: inert OPTIONS' do
    it 'leaves unrelated unsupported methods as route misses' do
      before_storage = secret_storage
      [:options, :put, :delete].each do |method|
        public_send(method, '/api/v3/status')
        expect(last_response.status).to eq(404)
        expect(last_response.headers['cache-control']).to eq('private, no-store')
      end
      expect(secret_storage).to eq(before_storage)
    end

    %w[v2 v3].each do |version|
      %w[generate conceal].each do |kind|
        it "does not create any records for #{version} OPTIONS #{kind}, even with a creation body" do
          before_storage = secret_storage
          options "/api/#{version}/secret/#{kind}",
            JSON.generate(secret: { secret: 'must not persist', ttl: 3600 }),
            {
              'CONTENT_TYPE' => 'application/json',
              'HTTP_ORIGIN' => 'https://external.example',
              'HTTP_ACCESS_CONTROL_REQUEST_METHOD' => 'POST',
              'HTTP_ACCESS_CONTROL_REQUEST_HEADERS' => 'content-type,authorization',
            }
          expect(secret_storage).to eq(before_storage)
          expect(last_response.status).to eq(204)
          expect(last_response.body).to eq('')
          expect(last_response.headers['cache-control']).to eq('private, no-store')
          expect(last_response.headers['x-request-id']).not_to be_nil
          expect(last_response.headers.keys.grep(/\Aaccess-control-allow-/i)).to be_empty
        end
      end

      it "does not bypass disabled guest generation through #{version} OPTIONS" do
        policy             = OT.conf['site']['interface']['api']['guest_routes']
        policy['enabled']  = false
        policy['generate'] = false
        before_storage     = secret_storage
        options "/api/#{version}/secret/generate"
        expect(secret_storage).to eq(before_storage)
        expect(last_response.status).to eq(204)
        anonymous_post "/api/#{version}/guest/secret/generate"
        expect(last_response.status).to eq(403)
        expect(secret_storage).to eq(before_storage)
      end
    end
  end

  describe 'HTTP-09: HEAD must not reach one-time operations' do
    %w[v2 v3].each do |version|
      it "REV-HTTP-001: preserves #{version} frozen route tables across repeated literal and dynamic HEAD" do
        router                = @http_boundary_routers.fetch("/api/#{version}")
        expect(router.frozen_configuration?).to be(true)
        expect(router.routes).to be_frozen
        expect(router.routes_literal).to be_frozen
        expect(router.route_handler_factory).to be_frozen
        routes_before         = router.routes.transform_values(&:dup)
        literals_before       = router.routes_literal.transform_values(&:dup)
        receipt_id, secret_id = create_pair(version: version, kind: 'generate')
        before_storage        = secret_storage

        2.times do
          head "/api/#{version}/status"
          expect(last_response.status).to eq(200)
          expect(last_response.body).to eq('')
          head "/api/#{version}/secret/http-boundary-missing/status"
          expect(last_response.status).to eq(200)
          expect(last_response.body).to eq('')
          head "/api/#{version}/guest/receipt/#{receipt_id}"
          expect(last_response.status).to eq(405)
          expect(last_response.headers['allow']).to eq('GET')
          expect(last_response.body).to eq('')
        end

        expect(secret_storage).to eq(before_storage)
        expect(Onetime::Secret.load(secret_id)&.viewable?).to be(true)
        expect(Onetime::Receipt.load(receipt_id).secret_value_shown_at.to_s).to be_empty
        expect(router.routes).to eq(routes_before)
        expect(router.routes_literal).to eq(literals_before)
        expect(router.routes).not_to have_key(:HEAD)
        expect(router.routes_literal).not_to have_key(:HEAD)
      end
    end

    {
      'v2' => %w[receipt private guest/receipt],
      'v3' => %w[receipt guest/receipt],
    }.each do |version, surfaces|
      surfaces.each do |surface|
        it "preserves the creator display slot at #{version}/#{surface}" do
          receipt_id, secret_id = create_pair(version: version, kind: 'generate')
          sign_in! if version == 'v3' && surface == 'receipt'
          before_storage = secret_storage
          head "/api/#{version}/#{surface}/#{receipt_id}"
          expect(secret_storage).to eq(before_storage)
          expect(Onetime::Receipt.load(receipt_id).secret_value_shown_at.to_s).to be_empty
          expect(Onetime::Secret.load(secret_id)).not_to be_nil
          expect(last_response.status).to eq(405)
          expect(last_response.headers['allow'].split(/,\s*/)).to include('GET')
          expect(last_response.headers['cache-control']).to eq('private, no-store')
          expect(last_response.body).to eq('')

          get "/api/#{version}/#{surface}/#{receipt_id}"
          expect(last_response.status).to eq(200), last_response.body
          expect(json_response.dig('details', 'secret_value')).not_to be_nil
          expect(Onetime::Receipt.load(receipt_id).secret_value_shown_at.to_s).not_to be_empty
        end
      end
    end

    %w[v2 v3].each do |version|
      %w[secret guest/secret].each do |surface|
        it "preserves the recipient reveal slot and GET-continue at #{version}/#{surface}" do
          receipt_id, secret_id = create_pair(version: version)
          sign_in! if version == 'v3' && surface == 'secret'
          before_storage = secret_storage
          head "/api/#{version}/#{surface}/#{secret_id}?continue=true"
          expect(secret_storage).to eq(before_storage)
          expect(Onetime::Secret.load(secret_id)&.viewable?).to be(true)
          expect(Onetime::Receipt.load(receipt_id).state).to eq('new')
          expect(last_response.status).to eq(405)
          expect(last_response.body).to eq('')
          expect(last_response.headers['cache-control']).to eq('private, no-store')

          get "/api/#{version}/#{surface}/#{secret_id}?continue=true"
          expect(last_response.status).to eq(200), last_response.body
          expect(json_response.dig('record', 'secret_value')).to eq('http boundary content')
          expect(Onetime::Secret.load(secret_id)).to be_nil
        end
      end

      it "keeps #{version} status HEAD available but bodyless" do
        head "/api/#{version}/status"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to eq('')
        expect(last_response.headers['cache-control']).to eq('private, no-store')
      end
    end

    it 'reports all supported methods when a HEAD path also names a literal POST operation' do
      sign_in!
      before_storage = secret_storage
      {
        'secret/generate' => %w[GET POST OPTIONS],
        'secret/conceal' => %w[GET POST OPTIONS],
        'secret/status' => %w[GET POST],
        'guest/secret/generate' => %w[GET POST],
        'guest/secret/conceal' => %w[GET POST],
      }.each do |path, allowed|
        %w[v2 v3].each do |version|
          head "/api/#{version}/#{path}"
          expect(last_response.status).to eq(405)
          expect(last_response.headers['allow'].split(/,\s*/)).to match_array(allowed)
          expect(last_response.body).to eq('')
        end
      end
      expect(secret_storage).to eq(before_storage)
    end

    it 'keeps Incoming config HEAD bodyless without changing secret storage' do
      before_storage = secret_storage
      head '/api/incoming/config'
      expect(last_response.status).to eq(200)
      expect(last_response.body).to eq('')
      expect(last_response.headers['cache-control']).to eq('private, no-store')
      expect(secret_storage).to eq(before_storage)
    end

    it 'keeps authenticated receipt listing HEAD available rather than treating recent as an identifier' do
      customer      = sign_in!
      head '/api/v3/receipt/recent'
      expect(last_response.status).to eq(200), last_response.body
      expect(last_response.body).to eq('')
      customer.regenerate_apitoken
      clear_cookies
      authorization = "Basic #{Base64.strict_encode64("#{customer.email}:#{customer.apitoken}")}"
      %w[receipt private].each do |surface|
        head "/api/v2/#{surface}/recent", {}, 'HTTP_AUTHORIZATION' => authorization
        expect(last_response.status).to eq(200), last_response.body
        expect(last_response.body).to eq('')
      end
    end

    it 'does not widen protected V3 HEAD access without a session' do
      receipt_id, secret_id = create_pair(kind: 'generate')
      clear_cookies
      before_storage        = secret_storage
      ["/api/v3/receipt/#{receipt_id}", "/api/v3/secret/#{secret_id}?continue=true", '/api/v3/version'].each do |path|
        head path
        expect(last_response.status).to eq(401)
        expect(last_response.body).to eq('')
        expect(last_response.headers['cache-control']).to eq('private, no-store')
      end
      expect(secret_storage).to eq(before_storage)
    end
  end

  describe 'HTTP-01/05/06: unchanged authentication, CSRF and throttling controls' do
    it 'keeps normal V3 secret creation session-only with Basic or Bearer headers' do
      customer = sign_in!
      customer.regenerate_apitoken
      clear_cookies
      basic    = "Basic #{Base64.strict_encode64("#{customer.email}:#{customer.apitoken}")}"
      [basic, 'Bearer invalid-boundary-token'].each do |authorization|
        before_storage = secret_storage
        anonymous_post '/api/v3/secret/generate', {}, 'HTTP_AUTHORIZATION' => authorization
        expect(last_response.status).to eq(401)
        expect(last_response.headers['cache-control']).to eq('private, no-store')
        expect(secret_storage).to eq(before_storage)
      end
    end

    it 'continues ignoring Basic and Bearer headers on explicit V3 guest creation' do
      customer = sign_in!
      customer.regenerate_apitoken
      clear_cookies
      basic    = "Basic #{Base64.strict_encode64("#{customer.email}:#{customer.apitoken}")}"
      [basic, 'Bearer invalid-boundary-token'].each do |authorization|
        anonymous_post '/api/v3/guest/secret/generate', {}, 'HTTP_AUTHORIZATION' => authorization
        expect(last_response.status).to eq(200), last_response.body
        receipt = Onetime::Receipt.load(json_response.dig('record', 'receipt', 'identifier'))
        expect(receipt.owner_id.to_s).to be_empty
        expect(last_request.env['otto.strategy_result'].auth_method).to eq('noauth')
      end
    end

    it 'retains session CSRF enforcement despite an ignored Bearer header' do
      sign_in!
      before_storage = secret_storage
      anonymous_post '/api/v3/secret/generate', {}, 'HTTP_AUTHORIZATION' => 'Bearer invalid-boundary-token'
      expect(last_response.status).to eq(403)
      expect(secret_storage).to eq(before_storage)
      expect(last_response.headers['cache-control']).to eq('private, no-store')
      post_json '/api/v3/secret/generate', {}, 'HTTP_AUTHORIZATION' => 'Bearer invalid-boundary-token'
      expect(last_response.status).to eq(200), last_response.body
      expect(last_request.env['otto.strategy_result'].auth_method).to eq('sessionauth')
    end

    it 'retains V2 Basic authentication for protected receipt listing' do
      customer = sign_in!
      customer.regenerate_apitoken
      clear_cookies
      get '/api/v2/receipt/recent', {}, 'HTTP_AUTHORIZATION' => "Basic #{Base64.strict_encode64("#{customer.email}:#{customer.apitoken}")}"
      expect(last_response.status).to eq(200), last_response.body
    end

    %w[v2 v3].each do |version|
      it "retains #{version} creation throttling while OPTIONS neither creates nor consumes quota" do
        OT.conf['site']['secret_options']['create_rate_limit'] = { 'enabled' => true, 'max_per_ip' => 1, 'window' => 60, 'lockout' => 60 }
        before_storage                                         = secret_storage
        options "/api/#{version}/secret/generate"
        expect(last_response.status).to eq(204)
        expect(secret_storage).to eq(before_storage)
        anonymous_post "/api/#{version}/guest/secret/generate"
        expect(last_response.status).to eq(200), last_response.body
        after_first                                            = secret_storage
        anonymous_post "/api/#{version}/guest/secret/generate"
        expect(last_response.status).to eq(429)
        expect(last_response.headers['retry-after']).to eq('60')
        expect(last_response.headers['cache-control']).to eq('private, no-store')
        expect(secret_storage).to eq(after_first)
        options "/api/#{version}/secret/generate"
        expect(last_response.status).to eq(204)
        expect(secret_storage).to eq(after_first)
      end
    end

    it 'does not relabel a dependency outage as a parser client error' do
      customer = sign_in!
      allow(Onetime::Customer).to receive(:find_by_extid).with(customer.extid).and_raise(Redis::CannotConnectError, 'isolated lookup failure')
      get '/api/v3/receipt/recent'
      expect(last_response.status).to eq(503)
      expect(last_response.headers['retry-after']).to eq('5')
      expect(last_response.headers['cache-control']).to eq('private, no-store')
    end
  end
end
