# spec/integration/simple/api_v3_schema_capture_spec.rb
#
# frozen_string_literal: true

# Fresh mounted-Rack producer captures for the Zod and generated OpenAPI gates.
# Run the complete file through tests/lanes/run simple --workers 1 --only this_file.
# Output is worktree-local tmp/api-v3-schema-captures (the lane scrubs custom env).
# Then set API_V3_SCHEMA_CAPTURE_DIR to that directory for the two TS gates.
# This replaces the archive-only probe; no vulnerability-asserting race is included.

require_relative '../integration_spec_helper'
require 'fileutils'

RSpec.describe 'V3 mounted producer schema captures', type: :integration do
  include_context 'auth_rack_test'

  let(:app) do
    @schema_capture_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
    @schema_capture_dir = File.expand_path('../../../tmp/api-v3-schema-captures', __dir__)
    FileUtils.mkdir_p(@schema_capture_dir)
  end

  before do
    clear_cookies
    # Only external email publication is stubbed; HTTP, auth and storage are real.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
  end

  def observe(name, method, path, payload: nil, response_schema:, request_schema: nil, status: 200, authenticated: false)
    env = { 'HTTP_ACCEPT' => 'application/json' }
    if payload
      env['CONTENT_TYPE'] = 'application/json'
      env['HTTP_X_CSRF_TOKEN'] = fetch_csrf_token if authenticated
      public_send(method, path, payload.to_json, env)
    else
      header 'Content-Type', nil
      public_send(method, path, {}, env)
    end

    body = JSON.parse(last_response.body)
    capture = {
      name: name, method: method.to_s.upcase, path: path, request: payload,
      response_schema: response_schema, request_schema: request_schema,
      status: last_response.status,
      # Do not export cookies, CSRF or credentials from the authenticated session.
      headers: last_response.headers.to_h.select { |key, _| key.match?(/\A(?:content-type|cache-control|x-request-id)\z/i) },
      body: body,
    }
    File.write(File.join(@schema_capture_dir, "#{name}.json"), JSON.pretty_generate(capture))
    expect(last_response.status).to eq(status), "#{method.upcase} #{path}: #{last_response.body}"
    body
  end

  def sign_in!
    customer = Onetime::Customer.new(email: "schema-capture-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase('Schema-Capture1234!')
    customer.verified = 'true'
    customer.save
    post_json '/auth/login', { login: customer.email, password: 'Schema-Capture1234!' }
    expect(last_response.status).to eq(200), last_response.body
  end

  def create_pair(name, prefix: '/api/v3/guest', kind: 'conceal', authenticated: false, content: {})
    value = { secret: "schema audit dummy #{name}", ttl: 3600 }.merge(content)
    value.delete(:secret) if kind == 'generate'
    body = observe(name, :post, "#{prefix}/secret/#{kind}", payload: { secret: value },
      response_schema: 'concealData', request_schema: "#{kind}Secret", authenticated: authenticated)
    record = body.fetch('record')
    [record.fetch('receipt').fetch('identifier'), record.fetch('secret').fetch('identifier')]
  end

  it 'captures authenticated reads, both status branches, CSV/array batches, memo and scopes' do
    sign_in!
    receipt, secret = create_pair('auth-conceal-minimal', prefix: '/api/v3', authenticated: true)
    generated_receipt, generated_secret = create_pair('auth-generate-minimal', prefix: '/api/v3', kind: 'generate', authenticated: true)
    {
      'auth-show-secret' => ["/api/v3/secret/#{secret}", 'secret'],
      'auth-show-receipt' => ["/api/v3/receipt/#{receipt}", 'receipt'],
      'status-found' => ["/api/v3/secret/#{secret}/status", 'secretStatus'],
      'status-missing' => ['/api/v3/secret/absent-schema-capture/status', 'secretStatus'],
      'auth-recent' => ['/api/v3/receipt/recent', 'receiptList'],
    }.each do |name, (path, schema)|
      observe(name, :get, path, response_schema: schema)
    end

    { 'status-csv' => "#{secret},#{generated_secret}", 'status-array' => [secret, generated_secret] }.each do |name, identifiers|
      body = observe(name, :post, '/api/v3/secret/status', payload: { identifiers: identifiers },
        response_schema: 'secretList', request_schema: 'listSecretStatus', authenticated: true)
      expect(body.fetch('records').map { |record| record.fetch('identifier') }.sort).to eq([secret, generated_secret].sort)
    end

    body = observe('auth-update-memo', :patch, "/api/v3/receipt/#{receipt}", payload: { memo: 'schema memo' },
      response_schema: 'updateReceipt', request_schema: 'updateReceipt', authenticated: true)
    expect(body.dig('record', 'memo')).to eq('schema memo')
    expect(Onetime::Receipt.load(receipt).memo).to eq('schema memo')

    { 'org' => 200, 'domain' => 422, 'nonsense' => 200 }.each do |scope, expected_status|
      observe("auth-recent-scope-#{scope}", :get, "/api/v3/receipt/recent?scope=#{scope}",
        response_schema: 'receiptList', status: expected_status)
    end
    [false, true].each do |proceed|
      observe("auth-reveal-#{proceed}", :post, "/api/v3/secret/#{secret}/reveal", payload: { continue: proceed },
        response_schema: 'secret', request_schema: 'revealSecret', authenticated: true)
      observe("auth-burn-#{proceed}", :post, "/api/v3/receipt/#{generated_receipt}/burn", payload: { continue: proceed },
        response_schema: 'receipt', request_schema: 'burnSecret', authenticated: true)
    end
    expect(Onetime::Secret.load(secret)).to be_nil
    expect(Onetime::Secret.load(generated_secret)).to be_nil
  end

  it 'captures guest operations and protected reveal confirmation variants' do
    receipt, secret = create_pair('guest-conceal', content: { passphrase: 'schema audit pass' })
    generated_receipt, = create_pair('guest-generate', kind: 'generate')
    observe('guest-show-secret', :get, "/api/v3/guest/secret/#{secret}", response_schema: 'secret')
    observe('guest-show-receipt', :get, "/api/v3/guest/receipt/#{receipt}", response_schema: 'receipt')
    body = observe('guest-batch', :post, '/api/v3/guest/receipts', payload: { identifiers: [receipt, generated_receipt] },
      response_schema: 'receiptList', request_schema: 'showMultipleReceipts')
    expect(body.fetch('count')).to eq(2)

    [false, true, 'true'].each do |proceed|
      if proceed == 'true'
        _, secret = create_pair('guest-conceal-string-confirm', content: { passphrase: 'schema audit pass' })
      end
      observe("guest-reveal-#{proceed.class.name}-#{proceed}", :post, "/api/v3/guest/secret/#{secret}/reveal",
        payload: { passphrase: 'schema audit pass', continue: proceed }, response_schema: 'secret', request_schema: 'revealSecret')
    end
    observe('guest-burn', :post, "/api/v3/guest/receipt/#{generated_receipt}/burn", payload: { continue: true },
      response_schema: 'receipt', request_schema: 'burnSecret')
  end

  it 'captures public metadata and authenticated version without exporting login credentials' do
    {
      'meta-status' => ['/api/v3/status', 'systemStatus', 200],
      'meta-locales' => ['/api/v3/supported-locales', 'supportedLocales', 200],
      'meta-version-anonymous' => ['/api/v3/version', 'systemVersion', 401],
    }.each do |name, (path, schema, status)|
      observe(name, :get, path, response_schema: schema, status: status)
    end
    sign_in!
    observe('meta-version-authenticated', :get, '/api/v3/version', response_schema: 'systemVersion')
  end

  it 'captures the bearer token grant with the operator flag on (#2427)' do
    allow(Onetime.auth_config).to receive(:paseto_enabled?).and_return(true)
    sign_in!
    body = observe('auth-token', :post, '/api/v3/token', payload: {}, response_schema: 'bearerToken', authenticated: true)
    expect(body.dig('record', 'token')).to start_with('v4.public.')
    expect(body.dig('record', 'token_type')).to eq('Bearer')
  end

  it 'captures accepted feedback and the rejected historical request shape' do
    observe('feedback-documented', :post, '/api/v3/feedback',
      payload: { message: 'schema audit obsolete body', email: 'schema@example.com' },
      response_schema: 'feedback', request_schema: 'receiveFeedback', status: 422)
    observe('feedback-actual', :post, '/api/v3/feedback', payload: { msg: 'schema audit feedback', tz: 'UTC' },
      response_schema: 'feedback', request_schema: 'receiveFeedback')
  end

  it 'captures Incoming config, recipient validation and nested creation' do
    old_incoming = OT.conf['features']['incoming']
    old_public = OT.incoming_public_recipients
    old_lookup = OT.incoming_recipient_lookup
    begin
      OT.conf['features']['incoming'] = old_incoming.merge('enabled' => true,
        'recipients' => [{ 'email' => 'schema-incoming@example.com', 'display_name' => 'Schema' }])
      Onetime::Initializers::SetupIncomingRecipients.new.execute(nil)
      config = observe('incoming-config', :get, '/api/incoming/config', response_schema: 'incomingConfig')
      digest = config.fetch('config').fetch('recipients').first.fetch('digest')
      [digest, 'absent-recipient'].each_with_index do |recipient, index|
        observe("incoming-validate-#{index}", :post, '/api/incoming/validate', payload: { recipient: recipient },
          response_schema: 'validateRecipient', request_schema: 'validateRecipient')
      end
      content = { secret: 'schema incoming dummy', recipient: digest, memo: 'schema memo' }
      observe('incoming-create-documented', :post, '/api/incoming/secret', payload: content,
        response_schema: 'incomingSecret', request_schema: 'createIncomingSecret', status: 422)
      observe('incoming-create-actual', :post, '/api/incoming/secret', payload: { secret: content },
        response_schema: 'incomingSecret', request_schema: 'createIncomingSecret')
    ensure
      OT.conf['features']['incoming'] = old_incoming
      OT.instance_variable_set(:@incoming_public_recipients, old_public)
      OT.instance_variable_set(:@incoming_recipient_lookup, old_lookup)
    end
  end

  it 'captures fully declared creation controls alongside the minimal bodies' do
    create_pair('guest-conceal-documented', content: { kind: 'conceal', share_domain: '' })
    create_pair('guest-generate-documented', kind: 'generate', content: {
      kind: 'generate', share_domain: '', length: 12,
      character_sets: { uppercase: true, lowercase: true, numbers: true, symbols: false },
    })
  end
end
