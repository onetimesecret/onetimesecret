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

  describe 'HTTP-05: expired active sessions' do
    %i[inactive absolute_expired].each do |state|
      it "refuses #{state} reads and both creation routes without reviving the SQL row" do
        header 'Content-Type', nil
        token = fetch_csrf_token
        expect(token).to be_a(String)
        expect(token).not_to be_empty
        @matrix_customer.regenerate_apitoken
        presented_header = "Basic #{Base64.strict_encode64("#{@matrix_customer.email}:#{@matrix_customer.apitoken}")}"
        get_json '/api/v3/receipt/recent'
        expect(last_response.status).to eq(200)
        expect(active_session_rows.count).to eq(1)

        apply_matrix_state!(state)
        before_storage = secret_storage
        get '/api/v3/receipt/recent', {}, { 'HTTP_ACCEPT' => 'application/json', 'HTTP_AUTHORIZATION' => presented_header }
        expect(last_response.status).to eq(401)
        expect(json_response).to include('code' => 'active_session_revoked', 'code_scope' => 'customer_session')
        expect(active_session_rows.count).to eq(0)
        expect(secret_storage).to eq(before_storage)

        %w[conceal generate].each do |operation|
          post_creation "/api/v3/secret/#{operation}", authorization: presented_header, csrf_token: token
          expect(last_response.status).to eq(401)
          expect(json_response).to include('code' => 'active_session_revoked', 'code_scope' => 'customer_session')
          expect(last_response.headers['www-authenticate']).to eq('Session realm="onetimesecret"')
          expect(active_session_rows.count).to eq(0)
          expect(secret_storage).to eq(before_storage)
        end
      end
    end
  end

  describe 'HTTP-05: surface-bound session replay' do
    let(:canonical_host) { 'auth-boundary.example.com' }

    around do |example|
      original_config = OT.conf.fetch('features').fetch('domains')
      original_features = Onetime::Runtime.features
      begin
        OT.conf['features']['domains'] = original_config.merge('enabled' => true, 'default' => canonical_host)
        Onetime::Runtime.features = original_features.with(domains_enabled: true)
        Onetime::Middleware::DomainStrategy.initialize_from_config(OT.conf['features']['domains'])
        header 'Host', canonical_host
        example.run
      ensure
        header 'Host', nil
        OT.conf['features']['domains'] = original_config
        Onetime::Runtime.features = original_features
        Onetime::Middleware::DomainStrategy.initialize_from_config(original_config)
      end
    end

    # Custom stamps are persisted fixtures, not SSO logins.
    %i[canonical_to_tenant tenant_to_canonical tenant_to_other_tenant].each do |boundary|
      it "refuses #{boundary} despite valid Basic credentials and CSRF" do
        org = Onetime::Organization.create!("Surface boundary #{SecureRandom.hex(6)}", @matrix_customer)
        domains = 2.times.map do
          host = "auth-#{SecureRandom.hex(8)}.tenant-example.com"
          domain = Onetime::CustomDomain.new(display_domain: host, org_id: org.org_id)
          domain.verified = true
          domain.save
          Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)
          domain
        end
        source_host = boundary == :canonical_to_tenant ? canonical_host : domains.first.display_domain
        target_host = boundary == :tenant_to_canonical ? canonical_host : domains.last.display_domain
        source_surface = if boundary == :canonical_to_tenant
                           Onetime::SessionSurface::CANONICAL
                         else
                           { 'kind' => 'custom', 'id' => domains.first.identifier }
                         end
        if boundary == :canonical_to_tenant
          expect(session_blob.fetch(Onetime::SessionSurface::KEY)).to eq(source_surface)
        else
          rewrite_session_blob { |blob| blob[Onetime::SessionSurface::KEY] = source_surface }
        end
        cookie = current_session_id
        @matrix_customer.regenerate_apitoken
        presented_header = "Basic #{Base64.strict_encode64("#{@matrix_customer.email}:#{@matrix_customer.apitoken}")}"
        env = { 'HTTP_HOST' => source_host, 'HTTP_COOKIE' => "onetime.session=#{cookie}",
                'HTTP_ACCEPT' => 'application/json' }
        header 'Content-Type', nil
        get '/api/v3/receipt/recent', {}, env
        expect(last_response.status).to eq(200)
        expect(Onetime::SessionSurface.for_env(last_request.env)).to eq(source_surface)
        expect(last_request.env.fetch('otto.strategy_result').user.objid).to eq(@matrix_customer.objid)
        token = last_response.headers['X-CSRF-Token']
        expect(token).to be_a(String)
        expect(token).not_to be_empty
        post '/api/v3/secret/conceal', { secret: { secret: 'matching surface', ttl: 3600 } }.to_json,
          env.merge('CONTENT_TYPE' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token)
        expect(last_response.status).to eq(200)
        record = json_response.fetch('record')
        expect(Onetime::Secret.load(record.fetch('secret').fetch('identifier')).owner_id).to eq(@matrix_customer.objid)
        before_storage = secret_storage

        env = env.merge('HTTP_HOST' => target_host, 'HTTP_AUTHORIZATION' => presented_header)
        get '/api/v3/receipt/recent', {}, env
        expect(last_response.status).to eq(401)
        expect(json_response).to include('code' => 'surface_mismatch', 'code_scope' => 'customer_session')
        expected_surface = boundary == :tenant_to_canonical ? Onetime::SessionSurface::CANONICAL :
          { 'kind' => 'custom', 'id' => domains.last.identifier }
        expect(Onetime::SessionSurface.for_env(last_request.env)).to eq(expected_surface)
        expect(secret_storage).to eq(before_storage)

        %w[conceal generate].each do |operation|
          post "/api/v3/secret/#{operation}", { secret: { secret: 'wrong surface', ttl: 3600 } }.to_json,
            env.merge('CONTENT_TYPE' => 'application/json', 'HTTP_X_CSRF_TOKEN' => token)
          expect(last_response.status).to eq(401)
          expect(json_response).to include('code' => 'surface_mismatch', 'code_scope' => 'customer_session')
          expect(last_response.headers['www-authenticate']).to eq('Session realm="onetimesecret"')
          expect(secret_storage).to eq(before_storage)
        end
      end
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
