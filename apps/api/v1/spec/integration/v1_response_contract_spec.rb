# apps/api/v1/spec/integration/v1_response_contract_spec.rb
#
# frozen_string_literal: true

# V1 API Response Contract Tests
#
# Verifies that V1 endpoints return flat JSON (not wrapped in
# {"success":true,"data":"..."} by Otto's JSONHandler). The wrapper
# bug occurs when routes use response=json; the fix uses response=default
# so Otto's DefaultHandler leaves res.body untouched.
#
# These tests exercise the full Rack stack: middleware -> Otto router ->
# response handler -> HTTP response. They require a running test Redis
# on port 2121 and a full application boot.
#
# Run:
#   pnpm run test:database:start
#   pnpm run test:rspec apps/api/v1/spec/integration/v1_response_contract_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'V1 API Response Contract', type: :integration do
  include Rack::Test::Methods

  # Use the full Rack::URLMap so requests traverse the complete middleware
  # stack (including CSRF bypass for /api/* paths) exactly as in production.
  def app
    @rack_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    Onetime.boot! :test
  end

  # The response=json wrapper adds top-level "success" and "data" keys;
  # flat responses must never have them.
  shared_examples 'flat JSON response' do
    it 'returns application/json content type' do
      expect(last_response.headers['content-type'] || last_response.content_type)
        .to include('application/json')
    end

    it 'returns valid JSON' do
      expect { JSON.parse(last_response.body) }.not_to raise_error
    end

    it 'does not contain a top-level success key' do
      body = JSON.parse(last_response.body)
      body = body.first if body.is_a?(Array)
      expect(body).not_to have_key('success') if body.is_a?(Hash)
    end

    it 'does not contain a top-level data wrapper key' do
      body = JSON.parse(last_response.body)
      body = body.first if body.is_a?(Array)
      expect(body).not_to have_key('data') if body.is_a?(Hash)
    end
  end

  describe 'GET /api/v1/status' do
    before { get '/api/v1/status' }
    include_examples 'flat JSON response'

    it 'returns status and locale at the top level' do
      body = JSON.parse(last_response.body)
      expect(body).to have_key('status')
      expect(body).to have_key('locale')
      expect(body['status']).to be_a(String)
      expect(body['locale']).to be_a(String)
    end
  end

  describe 'GET /api/v1/authcheck' do
    context 'without credentials' do
      before { get '/api/v1/authcheck' }
      include_examples 'flat JSON response'

      it 'returns 404 with message' do
        expect(last_response.status).to eq(404)
        body = JSON.parse(last_response.body)
        expect(body).to have_key('message')
        expect(body['message']).to eq('Not authorized')
      end
    end
  end

  describe 'POST /api/v1/generate' do
    before { post '/api/v1/generate', {} }
    include_examples 'flat JSON response'

    it 'returns receipt fields at the top level' do
      body = JSON.parse(last_response.body)
      expect(body).to have_key('custid')
      expect(body).to have_key('metadata_key')
      expect(body).to have_key('secret_key')
      expect(body).to have_key('ttl')
      expect(body).to have_key('metadata_ttl')
      expect(body).to have_key('secret_ttl')
      expect(body).to have_key('metadata_url')
      expect(body).to have_key('state')
      expect(body).to have_key('updated')
      expect(body).to have_key('created')
      expect(body).to have_key('recipient')
      expect(body).to have_key('value')
      expect(body).to have_key('passphrase_required')
    end

    it 'returns correct value types' do
      body = JSON.parse(last_response.body)
      expect(body['custid']).to be_a(String)
      expect(body['metadata_key']).to be_a(String)
      expect(body['secret_key']).to be_a(String)
      expect(body['ttl']).to be_a(Integer)
      expect(body['metadata_url']).to be_a(String)
      expect(body['metadata_url']).to include('/receipt/')
      expect(body['state']).to eq('new')
      expect(body['recipient']).to be_a(Array)
      expect(body['value']).to be_a(String)
      expect(body['passphrase_required']).to eq(false).or eq(true)
    end
  end

  describe 'POST /api/v1/share' do
    before { post '/api/v1/share', { secret: 'test secret value', ttl: 3600 } }
    include_examples 'flat JSON response'

    it 'returns receipt fields without value' do
      body = JSON.parse(last_response.body)
      expect(body).to have_key('custid')
      expect(body).to have_key('metadata_key')
      expect(body).to have_key('secret_key')
      expect(body).to have_key('ttl')
      expect(body).to have_key('metadata_url')
      expect(body).to have_key('state')
      expect(body).not_to have_key('value')
    end
  end

  describe 'POST /api/v1/create' do
    before { post '/api/v1/create', { secret: 'another secret', ttl: 3600 } }
    include_examples 'flat JSON response'

    it 'returns receipt fields without value' do
      body = JSON.parse(last_response.body)
      expect(body).to have_key('custid')
      expect(body).to have_key('metadata_key')
      expect(body).to have_key('secret_key')
      expect(body).to have_key('metadata_url')
      expect(body).to have_key('state')
      expect(body).not_to have_key('value')
    end
  end

  describe 'POST /api/v1/secret/:key' do
    context 'when secret exists' do
      # Anonymous-generated secrets have owner_id='anon'; load_owner
      # returns nil but show_secret now guards against this, allowing
      # the reveal to complete without crashing.
      let(:secret_key) do
        post '/api/v1/generate', {}
        JSON.parse(last_response.body)['secret_key']
      end

      before do
        key = secret_key
        post "/api/v1/secret/#{key}", {}
      end

      include_examples 'flat JSON response'

      it 'returns secret data with value, secret_key, and share_domain' do
        body = JSON.parse(last_response.body)
        expect(body).to have_key('value')
        expect(body).to have_key('secret_key')
        expect(body).to have_key('share_domain')
        expect(body['value']).to be_a(String)
      end
    end

    context 'when secret does not exist' do
      before { post '/api/v1/secret/nonexistent_key_abc123', {} }
      include_examples 'flat JSON response'

      it 'returns 404 with message' do
        expect(last_response.status).to eq(404)
        body = JSON.parse(last_response.body)
        expect(body).to have_key('message')
        expect(body['message']).to eq('Unknown secret')
        expect(body).to have_key('secret_key')
      end
    end
  end

  describe 'GET /api/v1/receipt/:key' do
    let(:receipt_key) do
      post '/api/v1/share', { secret: 'receipt test secret', ttl: 3600 }
      JSON.parse(last_response.body)['metadata_key']
    end

    before do
      key = receipt_key
      get "/api/v1/receipt/#{key}"
    end

    include_examples 'flat JSON response'

    it 'returns receipt fields at the top level' do
      body = JSON.parse(last_response.body)
      expect(body).to have_key('custid')
      expect(body).to have_key('metadata_key')
      expect(body).to have_key('metadata_url')
      expect(body).to have_key('ttl')
      expect(body).to have_key('state')
      expect(body).to have_key('updated')
      expect(body).to have_key('created')
    end
  end

  describe 'GET /api/v1/receipt/recent' do
    context 'without credentials' do
      before { get '/api/v1/receipt/recent' }
      include_examples 'flat JSON response'

      it 'returns 404' do
        expect(last_response.status).to eq(404)
        body = JSON.parse(last_response.body)
        expect(body).to have_key('message')
      end
    end
  end

  describe 'POST /api/v1/receipt/:key/burn' do
    context 'when receipt exists and secret is burnable' do
      # Anonymous-generated secrets have owner_id='anon'; load_owner
      # returns nil but burn_secret now guards against this.
      let(:receipt_key) do
        post '/api/v1/share', { secret: 'burn test secret', ttl: 3600 }
        JSON.parse(last_response.body)['metadata_key']
      end

      before do
        key = receipt_key
        post "/api/v1/receipt/#{key}/burn", { continue: 'true' }
      end

      include_examples 'flat JSON response'

      it 'returns burn data with state and secret_shortkey' do
        body = JSON.parse(last_response.body)
        expect(body).to have_key('state')
        expect(body).to have_key('secret_shortkey')
        expect(body['state']).to be_a(Hash)
        expect(body['secret_shortkey']).to be_a(String)
      end
    end

    context 'when receipt does not exist' do
      before { post '/api/v1/receipt/nonexistent_key_xyz/burn', {} }
      include_examples 'flat JSON response'

      it 'returns 404 with message' do
        expect(last_response.status).to eq(404)
        body = JSON.parse(last_response.body)
        expect(body).to have_key('message')
      end
    end
  end

  # Keys shorter than V1_MIN_IDENTIFIER_LENGTH (20) are rejected early
  # by valid_identifier? — exercises the otto_not_found code path.
  describe 'short key rejection (valid_identifier? guard)' do
    %w[show_secret show_receipt burn_secret].zip([
      ->(key) { post "/api/v1/secret/#{key}", {} },
      ->(key) { get  "/api/v1/receipt/#{key}" },
      ->(key) { post "/api/v1/receipt/#{key}/burn", {} },
    ]).each do |label, request_proc|
      context "#{label} with sub-20-char key" do
        before { request_proc.call('short') }
        include_examples 'flat JSON response'

        it 'returns 404 with message key (not error key)' do
          expect(last_response.status).to eq(404)
          body = JSON.parse(last_response.body)
          expect(body).to have_key('message')
          expect(body).not_to have_key('error')
        end
      end
    end
  end
end
