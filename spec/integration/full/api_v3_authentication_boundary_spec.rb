# frozen_string_literal: true

require_relative '../integration_spec_helper'
require_relative '../../support/customer_session_failure_matrix'
require 'base64'

# HTTP-05.R1: use the existing real full-mode login and active-session helpers.
RSpec.describe 'V3 current authentication boundaries in full mode', type: :integration do
  include_context 'auth_rack_test'
  include CustomerSessionFailureMatrix

  let(:matrix_password) { 'Authentication-Boundary1234!' }
  let(:app) do
    @authentication_boundary_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

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
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
    establish_matrix_session!
  end

  def post_creation(path, authorization:, csrf_token: nil)
    env = { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json',
            'HTTP_AUTHORIZATION' => authorization }
    env['HTTP_X_CSRF_TOKEN'] = csrf_token if csrf_token
    post path, { secret: { secret: 'full authentication boundary fixture', ttl: 3600 } }.to_json, env
  end

  def secret_storage
    [Onetime::Secret, Onetime::Receipt].to_h do |model|
      keys = model.dbclient.scan_each(match: "#{model.prefix}:*").to_a.sort
      [model.name, keys.to_h { |key| [key, model.dbclient.dump(key)] }]
    end
  end

  { revoked: 'active_session_revoked', suspended: 'account_suspended' }.each do |state, code|
    it "refuses #{state} protected creation without header fallback but keeps the guest CSRF boundary" do
      @matrix_customer.regenerate_apitoken
      presented_header = "Basic #{Base64.strict_encode64("#{@matrix_customer.email}:#{@matrix_customer.apitoken}")}"
      header 'Content-Type', nil
      token = fetch_csrf_token
      expect(token).to be_a(String)
      expect(token).not_to be_empty

      get_json '/api/v3/receipt/recent'
      expect(last_response.status).to eq(200)
      expect(last_request.env.fetch('otto.strategy_result').user.objid).to eq(@matrix_customer.objid)
      expect(active_session_rows.count).to eq(1)

      if state == :revoked
        expect(active_session_rows.delete).to eq(1)
      else
        @matrix_customer.suspended!('true')
      end
      before_storage = secret_storage

      post_creation '/api/v3/secret/conceal', authorization: presented_header, csrf_token: token
      expect(last_response.status).to eq(401)
      expect(json_response).to include('code' => code, 'code_scope' => 'customer_session')
      expect(last_response.headers['www-authenticate']).to eq('Session realm="onetimesecret"')
      expect(secret_storage).to eq(before_storage)

      post_creation '/api/v3/guest/secret/conceal', authorization: presented_header
      expect(last_response.status).to eq(403)
      expect(last_request.env['onetime.csrf.rejected']).to be(true)
      expect(secret_storage).to eq(before_storage)

      post_creation '/api/v3/guest/secret/conceal', authorization: presented_header, csrf_token: token
      expect(last_response.status).to eq(200)
      record = json_response.fetch('record')
      receipt = Onetime::Receipt.load(record.fetch('receipt').fetch('identifier'))
      secret = Onetime::Secret.load(record.fetch('secret').fetch('identifier'))
      expect(receipt).to have_attributes(owner_id: nil, source: 'standard', secret_identifier: secret.identifier)
      expect(secret).to have_attributes(owner_id: nil, receipt_identifier: receipt.identifier)
      result = last_request.env.fetch('otto.strategy_result')
      expect(result.auth_method).to eq('noauth')
      expect(result.user).to be_nil
    end
  end
end
