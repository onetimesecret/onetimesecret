# frozen_string_literal: true

require_relative '../integration_spec_helper'

RSpec.describe 'Mounted V2/V3 receipt scopes', type: :integration do
  include_context 'auth_rack_test'

  let(:app) do
    @receipt_scope_app ||= begin
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

  ['/api/v2', '/api/v3'].each do |prefix|
    describe prefix do
      before do
        basic_authorize @receipt_customer.email, @receipt_customer.apitoken if prefix == '/api/v2'
      end

      ['scope[]=org', 'scope[x]=org'].each do |query|
        it "returns a controlled client error for #{query}" do
          get "#{prefix}/receipt/recent?#{query}", {}, { 'HTTP_ACCEPT' => 'application/json' }
          expect(last_response.status).to eq(422), last_response.body
          expect(last_response.body).to include('Invalid scope')
        end
      end

      it 'retains the default and unknown-scalar personal-scope controls' do
        ['', '?scope=nonsense'].each do |query|
          get "#{prefix}/receipt/recent#{query}", {}, { 'HTTP_ACCEPT' => 'application/json' }
          expect(last_response.status).to eq(200), last_response.body
        end
      end
    end
  end
end
