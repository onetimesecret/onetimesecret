# spec/unit/apps/api/v1/controllers/index_spec.rb

require_relative '../../../../../spec_helper'
require 'v1/controllers'

RSpec.describe V1::Controllers::Index, type: :request do
  include_context "rack_test_context"

  let(:request) { rack_request }
  let(:response) { rack_response }

  let(:app) { described_class.new request, response }

  let(:session_id) { 'test_session_123' }
  let(:customer_id) { 'test@example.com' }
  let(:ip_address) { '127.0.0.1' }

  let(:session) do
    instance_double(V1::Session,
      sessid: session_id,
      event_incr!: true,
      authenticated?: true,
      anonymous?: false,
      ipaddress: ip_address,
      external_identifier: 'ext123')
  end

  let(:customer) do
    instance_double(V1::Customer,
      custid: customer_id,
      anonymous?: false,
      active?: true,
      verified?: true,
      role: 'customer',
      increment_field: nil,
      email: 'test@example.com')
  end


  before do
    allow(app).to receive(:sess).and_return(session)
    allow(app).to receive(:cust).and_return(customer)
    allow(app).to receive(:req).and_return(request)
    allow(app).to receive(:res).and_return(response)
    allow(app).to receive(:locale).and_return('en')
    allow(app).to receive(:authorized).and_yield
  end

  describe '#show_secret' do
    let(:secret_key) { 'test_secret_key' }
    let(:logic) { instance_double(V1::Logic::Secrets::ShowSecret) }
    let(:secret_params) { {key: secret_key, continue: 'true'} }

    before do
      allow(request).to receive(:params).and_return(secret_params)
      allow(V1::Logic::Secrets::ShowSecret).to receive(:new)
        .with(session, customer, secret_params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
    end

    context 'when secret is available' do
      let(:secret_value) { 'secret_content' }
      let(:share_domain) { 'example.com' }

      before do
        allow(logic).to receive(:show_secret).and_return(true)
        allow(logic).to receive(:secret_value).and_return(secret_value)
        allow(logic).to receive(:share_domain).and_return(share_domain)
      end

      it 'returns secret data as JSON' do
        expect(app).to receive(:json).with(
          value: secret_value,
          secret_key: secret_key,
          share_domain: share_domain,
        )
        app.show_secret
      end
    end

    context 'when secret is not found' do
      before do
        allow(logic).to receive(:show_secret).and_return(false)
        allow(app).to receive(:secret_not_found_response)
      end

      it 'returns not found response' do
        expect(app).to receive(:secret_not_found_response)
        app.show_secret
      end
    end
  end

  describe '#share' do
    let(:logic) { instance_double(V1::Logic::Secrets::ConcealSecret) }
    let(:secret) do
      double('V1::Secret',
        realttl: 3600,
        has_passphrase?: false,
        key: 'secret_key_123')
    end
    let(:metadata) do
      double('V1::Metadata',
        key: 'metadata_key_123',
        viewed!: nil)
    end

    before do
      allow(V1::Logic::Secrets::ConcealSecret).to receive(:new)
        .with(session, customer, {secret: request.params}, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      allow(logic).to receive(:secret).and_return(secret)
      allow(logic).to receive(:metadata).and_return(metadata)
      allow(described_class).to receive(:metadata_hsh).and_return({
        key: 'metadata_key_123',
        secret_ttl: 3600,
        passphrase_required: false
      })
    end

    it 'processes share request and returns metadata' do
      expect(app).to receive(:json).with(
        hash_including(
          key: 'metadata_key_123',
          secret_ttl: 3600,
          passphrase_required: false,
        ),
      )
      app.share
    end

    context 'when request is GET' do
      before do
        allow(request).to receive(:get?).and_return(true)
        allow(logic).to receive(:redirect_uri).and_return('/some/path')
      end

      it 'redirects to the specified path' do
        expect(response).to receive(:redirect).with('/some/path')
        app.share
      end
    end
  end

  describe '#status' do
    it 'returns system status' do
      expect(app).to receive(:json).with(
        status: :nominal,
        locale: 'en',
      )
      app.status
    end

    it 'increments status check counter' do
      expect(session).to receive(:event_incr!).with(:check_status)
      app.status
    end
  end

  describe '#authcheck' do
    it 'returns status without requiring authorization' do
      expect(app).to receive(:json).with(
        status: :nominal,
        locale: 'en',
      )
      app.authcheck
    end
  end
end
