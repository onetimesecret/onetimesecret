# apps/api/v1/spec/controllers/anonymous_access_spec.rb
#
# frozen_string_literal: true

# Integration specs for the anonymous access paths through V1 API endpoints.
#
# The `authorized` method (base.rb:48-91) has three code paths:
#   1. Credentials provided (Basic Auth) - validates customer + apitoken
#   2. No credentials, allow_anonymous=true - @cust stays nil
#   3. No credentials, allow_anonymous=false - raises OT::Unauthorized
#
# The existing controller specs in index_spec.rb stub out `authorized`
# entirely with `allow(app).to receive(:authorized).and_yield`, so
# none of these paths are exercised. This file tests them directly.

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')
require 'v1/controllers'

RSpec.describe V1::Controllers::Index, 'anonymous access paths' do
  include_context "rack_test_context"

  let(:request) { rack_request }
  let(:response) { rack_response }

  let(:app) { described_class.new request, response }

  # Env hash that `authorized` reads and mutates (adds 'otto.auth')
  let(:env) do
    {
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_HOST' => 'example.com',
      'rack.session' => {},
      'HTTP_ACCEPT' => 'application/json',
      'ots.locale' => 'en',
    }
  end

  # Anonymous users have nil cust - no Customer.anonymous singleton

  before do
    allow(request).to receive(:env).and_return(env)
    allow(request).to receive(:params).and_return({})
    allow(request).to receive(:client_ipaddress).and_return('127.0.0.1')
    allow(request).to receive(:request_path).and_return('/api/v1/test')
    allow(request).to receive(:path).and_return('/api/v1/test')
    allow(request).to receive(:current_absolute_uri).and_return('http://example.com/api/v1/test')
    allow(request).to receive(:cookies).and_return({})
    allow(request).to receive(:request_method).and_return('POST')
    allow(request).to receive(:ip).and_return('127.0.0.1')
    allow(request).to receive(:query_string).and_return('')
    allow(request).to receive(:user_agent).and_return('rspec-test')

    allow(response).to receive(:status=)
    allow(response).to receive(:do_not_cache!)

    # Silence logging
    allow(OT).to receive(:ld)
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)
  end

  # ------------------------------------------------------------------
  # The `authorized` method itself — three code paths
  # ------------------------------------------------------------------
  describe '#authorized (method behavior)' do
    context 'path 1: no credentials, allow_anonymous=true' do
      it 'leaves @cust as nil and yields' do
        yielded = false

        app.authorized(true) do
          yielded = true
        end

        expect(yielded).to be true
        expect(app.cust).to be_nil
      end
    end

    context 'path 2: no credentials, allow_anonymous=false' do
      it 'does not yield and returns a 404 error response' do
        yielded = false

        app.authorized(false) do
          yielded = true
        end

        expect(yielded).to be false
      end

      it 'calls not_authorized_error (caught by carefully)' do
        # OT::Unauthorized is rescued by `carefully` which calls
        # not_authorized_error, setting res.status = 404
        expect(response).to receive(:status=).with(404)

        app.authorized(false) { }
      end
    end

    context 'path 3: Basic Auth credentials provided' do
      let(:custid) { 'user@example.com' }
      let(:apitoken) { 'valid_token_abc' }

      let(:authenticated_customer) do
        instance_double(Onetime::Customer,
          custid: custid,
          email: custid,
          anonymous?: false,
          active?: true,
          verified?: true,
          role: 'customer',
          locale: 'en',
          obscure_email: 'u***@example.com',
          increment_field: nil)
      end

      before do
        # Encode Basic Auth into the env
        encoded = Base64.strict_encode64("#{custid}:#{apitoken}")
        env['HTTP_AUTHORIZATION'] = "Basic #{encoded}"

        allow(OT).to receive(:conf).and_return({
          'site' => {
            'authentication' => { 'enabled' => true, 'signin' => true },
            'security' => { 'csp' => { 'enabled' => false } },
          },
          'development' => { 'enabled' => false },
        })
      end

      context 'when customer exists and apitoken matches' do
        before do
          allow(Onetime::Customer).to receive(:load_by_extid_or_email)
            .with(custid).and_return(authenticated_customer)
          allow(authenticated_customer).to receive(:apitoken?)
            .with(apitoken).and_return(true)
        end

        it 'sets @cust to the authenticated customer and yields' do
          yielded = false

          app.authorized(false) do
            yielded = true
          end

          expect(yielded).to be true
          expect(app.cust).to eq(authenticated_customer)
        end
      end

      context 'when customer exists but apitoken is wrong' do
        before do
          allow(Onetime::Customer).to receive(:load_by_extid_or_email)
            .with(custid).and_return(authenticated_customer)
          allow(authenticated_customer).to receive(:apitoken?)
            .with(apitoken).and_return(false)
        end

        it 'does not yield (unauthorized)' do
          yielded = false

          app.authorized(false) do
            yielded = true
          end

          expect(yielded).to be false
        end
      end

      context 'when customer does not exist' do
        before do
          allow(Onetime::Customer).to receive(:load_by_extid_or_email)
            .with(custid).and_return(nil)
        end

        it 'does not yield (unauthorized)' do
          yielded = false

          app.authorized(false) do
            yielded = true
          end

          expect(yielded).to be false
        end
      end

      context 'when authentication is disabled' do
        before do
          allow(OT).to receive(:conf).and_return({
            'site' => {
              'authentication' => { 'enabled' => false, 'signin' => false },
              'security' => { 'csp' => { 'enabled' => false } },
            },
            'development' => { 'enabled' => false },
          })
        end

        it 'returns disabled_response (404) instead of authenticating' do
          expect(response).to receive(:status=).with(404)

          app.authorized(false) { }
        end
      end
    end
  end

  # ------------------------------------------------------------------
  # Endpoints that pass allow_anonymous: true
  # ------------------------------------------------------------------
  describe 'endpoints that allow anonymous access' do
    # Stub the logic layer so we only test the auth path, not business logic.
    # The controller action must reach the yield block and execute.

    describe '#status (authorized true)' do
      it 'succeeds without credentials' do
        expect(app).to receive(:json).with(hash_including(status: :nominal))
        app.status
      end

      it 'leaves cust as nil for anonymous' do
        allow(app).to receive(:json)
        app.status
        expect(app.cust).to be_nil
      end
    end

    describe '#share (authorized true)' do
      let(:logic) { instance_double(V1::Logic::Secrets::ConcealSecret) }
      let(:secret) do
        double('Onetime::Secret',
          current_expiration: 3600,
          has_passphrase?: false)
      end
      let(:receipt) { double('Onetime::Receipt', key: 'rcpt_anon') }

      before do
        allow(V1::Logic::Secrets::ConcealSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(secret)
        allow(logic).to receive(:receipt).and_return(receipt)
        allow(described_class).to receive(:receipt_hsh).and_return({ 'metadata_key' => 'rcpt_anon' })
      end

      it 'succeeds without credentials with nil customer' do
        allow(app).to receive(:json)
        app.share
        expect(app.cust).to be_nil
      end
    end

    describe '#generate (authorized true)' do
      let(:logic) { instance_double(V1::Logic::Secrets::GenerateSecret) }
      let(:secret) do
        double('Onetime::Secret',
          current_expiration: 3600,
          has_passphrase?: false)
      end
      let(:receipt) { double('Onetime::Receipt', key: 'rcpt_gen', previewed!: nil) }

      before do
        allow(V1::Logic::Secrets::GenerateSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(secret)
        allow(logic).to receive(:receipt).and_return(receipt)
        allow(logic).to receive(:secret_value).and_return('generated123')
        allow(described_class).to receive(:receipt_hsh).and_return({ 'value' => 'generated123' })
      end

      it 'succeeds without credentials' do
        allow(app).to receive(:json)
        app.generate
        expect(app.cust).to be_nil
      end
    end

    describe '#create (authorized true)' do
      let(:logic) { instance_double(V1::Logic::Secrets::ConcealSecret) }
      let(:secret) do
        double('Onetime::Secret',
          current_expiration: 7200,
          has_passphrase?: false)
      end
      let(:receipt) { double('Onetime::Receipt', key: 'rcpt_create') }

      before do
        allow(V1::Logic::Secrets::ConcealSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(secret)
        allow(logic).to receive(:receipt).and_return(receipt)
        allow(described_class).to receive(:receipt_hsh).and_return({ 'metadata_key' => 'rcpt_create' })
      end

      it 'succeeds without credentials' do
        allow(app).to receive(:json)
        app.create
        expect(app.cust).to be_nil
      end
    end

    describe '#show_secret (authorized true)' do
      let(:logic) { instance_double(V1::Logic::Secrets::ShowSecret) }

      before do
        allow(request).to receive(:params).and_return({ 'key' => 'secret_abc' })
        allow(V1::Logic::Secrets::ShowSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:show_secret).and_return(false)
      end

      it 'reaches the controller block without credentials' do
        allow(app).to receive(:secret_not_found_response)
        app.show_secret
        expect(app.cust).to be_nil
      end
    end

    describe '#show_receipt (authorized true)' do
      let(:logic) { instance_double(V1::Logic::Secrets::ShowReceipt) }
      let(:receipt) do
        double('Onetime::Receipt',
          key: 'rcpt_show',
          previewed!: nil)
      end

      before do
        allow(request).to receive(:params).and_return({ 'key' => 'rcpt_key' })
        allow(V1::Logic::Secrets::ShowReceipt).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:show_secret).and_return(false)
        allow(logic).to receive(:receipt).and_return(receipt)
        allow(logic).to receive(:secret_realttl).and_return(3600)
        allow(logic).to receive(:has_passphrase).and_return(false)
        allow(described_class).to receive(:receipt_hsh).and_return({ 'metadata_key' => 'rcpt_show' })
      end

      it 'succeeds without credentials' do
        allow(app).to receive(:json)
        app.show_receipt
        expect(app.cust).to be_nil
      end
    end
  end

  # ------------------------------------------------------------------
  # Endpoints that pass allow_anonymous: false
  # ------------------------------------------------------------------
  describe 'endpoints that deny anonymous access' do
    describe '#show_receipt_recent (authorized false)' do
      it 'returns 404 without credentials' do
        expect(response).to receive(:status=).with(404)
        app.show_receipt_recent
      end

      it 'does not reach the controller logic' do
        expect(V1::Logic::Secrets::ShowReceiptList).not_to receive(:new)
        app.show_receipt_recent
      end
    end

    describe '#authcheck (authorized false)' do
      it 'returns 404 without credentials' do
        expect(response).to receive(:status=).with(404)
        app.authcheck
      end
    end
  end
end
