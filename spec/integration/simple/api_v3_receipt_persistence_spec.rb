# frozen_string_literal: true

require_relative '../integration_spec_helper'

RSpec.describe 'Mounted V2/V3 receipt persistence', type: :integration do
  include_context 'auth_rack_test'

  let(:app) do
    @receipt_persistence_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) { Onetime.boot! :test }

  before do
    clear_cookies
    header 'Authorization', nil
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
    customer = Onetime::Customer.new(email: "receipt-persistence-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase('Receipt-Persistence1234!')
    customer.verified = 'true'
    customer.apitoken = SecureRandom.hex(20)
    customer.save
    post_json '/auth/login', { login: customer.email, password: 'Receipt-Persistence1234!' }
    expect(last_response.status).to eq(200), last_response.body
    @receipt_customer = customer
  end

  def patch_memo(path)
    patch path, { memo: 'mounted concurrent memo' }.to_json,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json',
        'HTTP_X_CSRF_TOKEN' => fetch_csrf_token }
  end

  ['/api/v2', '/api/v3'].each do |prefix|
    describe prefix do
      before do
        basic_authorize @receipt_customer.email, @receipt_customer.apitoken if prefix == '/api/v2'
      end

      it 'does not repeat creator plaintext when PATCH resumes after a real guest preview' do
        post_json "#{prefix}/secret/generate", { secret: { ttl: 3600 } }
        expect(last_response.status).to eq(200), last_response.body
        receipt_id = JSON.parse(last_response.body).dig('record', 'receipt', 'identifier')
        expect(receipt_id).to be_a(String)
        first_value = nil
        first_marker = nil
        interleavings = 0

        # Pause only scheduling: authentication, ownership, entitlement checks,
        # both Rack requests and every datastore operation remain real.
        allow_any_instance_of(V2::Logic::Secrets::UpdateReceipt).to receive(:process).and_wrap_original do |original|
          interleavings += 1
          response = Rack::MockRequest.new(app).get("#{prefix}/guest/receipt/#{receipt_id}",
            'HTTP_ACCEPT' => 'application/json')
          expect(response.status).to eq(200), response.body
          first_value = JSON.parse(response.body).dig('details', 'secret_value')
          first_marker = Onetime::Receipt.load(receipt_id).secret_value_shown_at
          original.call
        end

        patch_memo("#{prefix}/receipt/#{receipt_id}")
        expect(last_response.status).to eq(200), last_response.body
        expect(interleavings).to eq(1)
        expect(first_value).to be_a(String)
        expect(first_value).not_to be_empty
        expect(first_marker).to be_positive
        stored = Onetime::Receipt.load(receipt_id)
        expect(stored.secret_value_shown_at).to eq(first_marker)
        expect(stored.memo).to eq('mounted concurrent memo')
        expect(JSON.parse(last_response.body).dig('record', 'memo')).to eq('mounted concurrent memo')

        get "#{prefix}/guest/receipt/#{receipt_id}", {}, { 'HTTP_ACCEPT' => 'application/json' }
        expect(last_response.status).to eq(200), last_response.body
        expect(JSON.parse(last_response.body).dig('details', 'secret_value')).to be_nil
      end

    end
  end
end
