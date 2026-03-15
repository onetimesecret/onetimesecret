# apps/api/v1/spec/controllers/index_spec.rb
#
# frozen_string_literal: true

require_relative '../../application'
require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative File.join(Onetime::HOME, 'spec', 'support', 'model_test_helper.rb')
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
    double('Session',
      sessid: session_id,
      authenticated?: true,
      anonymous?: false,
      ipaddress: ip_address,
      external_identifier: 'ext123')
  end

  let(:customer) do
    instance_double(Onetime::Customer,
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
    # Stub rate limiting so existing specs don't hit Redis or fail on
    # unstubbed customer.planid / request.client_ipaddress calls.
    allow(app).to receive(:check_rate_limit!).and_return(nil)
  end

  describe '#show_secret' do
    let(:secret_key) { 'test_secret_key_abcdefg' }
    let(:logic) { instance_double(V1::Logic::Secrets::ShowSecret) }
    let(:secret_params) { {'key' => secret_key, 'continue' => 'true'} }

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
      double('Onetime::Secret',
        realttl: 3600,
        current_expiration: 3600,
        has_passphrase?: false,
        key: 'secret_key_123')
    end
    let(:receipt) do
      double('Onetime::Receipt',
        key: 'receipt_key_123')
    end

    before do
      allow(V1::Logic::Secrets::ConcealSecret).to receive(:new)
        .with(session, customer, request.params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      allow(logic).to receive(:secret).and_return(secret)
      allow(logic).to receive(:receipt).and_return(receipt)
      allow(described_class).to receive(:receipt_hsh).and_return({
        key: 'receipt_key_123',
        secret_ttl: 3600,
        passphrase_required: false
      })
    end

    it 'processes share request and returns metadata' do
      expect(app).to receive(:json).with(
        hash_including(
          key: 'receipt_key_123',
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
        allow(request).to receive(:app_path).and_return('/some/path')
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

  describe '#create' do
    # #create uses ConcealSecret, identical to #share.
    let(:logic) { instance_double(V1::Logic::Secrets::ConcealSecret) }
    let(:secret) do
      double('Onetime::Secret',
        current_expiration: 7200,
        has_passphrase?: false)
    end
    let(:receipt) do
      double('Onetime::Receipt', key: 'receipt_key_create')
    end

    before do
      allow(V1::Logic::Secrets::ConcealSecret).to receive(:new)
        .with(session, customer, request.params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      allow(logic).to receive(:secret).and_return(secret)
      allow(logic).to receive(:receipt).and_return(receipt)
      allow(described_class).to receive(:receipt_hsh).and_return({
        'metadata_key' => 'receipt_key_create',
        'secret_ttl' => 7200,
        'passphrase_required' => false,
      })
    end

    it 'returns receipt hash as JSON' do
      expect(app).to receive(:json).with(
        hash_including('metadata_key' => 'receipt_key_create'),
      )
      app.create
    end

    context 'when request is GET' do
      before do
        allow(request).to receive(:get?).and_return(true)
        allow(logic).to receive(:redirect_uri).and_return('/receipt/abc')
        allow(request).to receive(:app_path).and_return('/receipt/abc')
      end

      it 'redirects' do
        expect(response).to receive(:redirect).with('/receipt/abc')
        app.create
      end
    end
  end

  describe '#generate' do
    let(:logic) { instance_double(V1::Logic::Secrets::GenerateSecret) }
    let(:secret) do
      double('Onetime::Secret',
        current_expiration: 3600,
        has_passphrase?: false)
    end
    let(:receipt) do
      double('Onetime::Receipt', key: 'receipt_key_gen', previewed!: nil)
    end
    let(:generated_value) { 'r4nd0mPa55!' }

    before do
      allow(V1::Logic::Secrets::GenerateSecret).to receive(:new)
        .with(session, customer, request.params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      allow(logic).to receive(:secret).and_return(secret)
      allow(logic).to receive(:receipt).and_return(receipt)
      allow(logic).to receive(:secret_value).and_return(generated_value)
      allow(described_class).to receive(:receipt_hsh).and_return({
        'metadata_key' => 'receipt_key_gen',
        'value' => generated_value,
        'secret_ttl' => 3600,
        'passphrase_required' => false,
      })
    end

    it 'includes :value (the generated password) in the JSON response' do
      expect(app).to receive(:json).with(
        hash_including('value' => generated_value),
      )
      app.generate
    end

    it 'calls previewed! on the receipt after responding' do
      allow(app).to receive(:json)
      expect(receipt).to receive(:previewed!)
      app.generate
    end

    context 'when request is GET' do
      before do
        allow(request).to receive(:get?).and_return(true)
        allow(logic).to receive(:redirect_uri).and_return('/receipt/gen')
        allow(request).to receive(:app_path).and_return('/receipt/gen')
      end

      it 'redirects without calling previewed!' do
        expect(response).to receive(:redirect).with('/receipt/gen')
        expect(receipt).not_to receive(:previewed!)
        app.generate
      end
    end
  end

  describe '#show_secret (passphrase required case)' do
    # The existing context covers show_secret=true and show_secret=false (not found).
    # This adds the passphrase-required case: secret exists but correct_passphrase is false.
    let(:secret_key) { 'locked_secret_key_abcde' }
    let(:logic) { instance_double(V1::Logic::Secrets::ShowSecret) }
    let(:secret_params) { {'key' => secret_key, 'continue' => 'true'} }

    before do
      allow(request).to receive(:params).and_return(secret_params)
      allow(V1::Logic::Secrets::ShowSecret).to receive(:new)
        .with(session, customer, secret_params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      # show_secret is false when passphrase is wrong — same controller path as
      # "not found", so secret_not_found_response is called.
      allow(logic).to receive(:show_secret).and_return(false)
      allow(app).to receive(:secret_not_found_response)
    end

    it 'calls secret_not_found_response when passphrase is wrong' do
      expect(app).to receive(:secret_not_found_response)
      app.show_secret
    end
  end

  describe '#burn_secret' do
    let(:receipt_key) { 'receipt_key_burn_abcde' }
    let(:logic) { instance_double(V1::Logic::Secrets::BurnSecret) }
    let(:burn_params) { {'key' => receipt_key, 'continue' => 'true'} }
    let(:receipt) do
      double('Onetime::Receipt',
        key: receipt_key,
        secret_shortid: 'shortid123')
    end

    before do
      allow(request).to receive(:params).and_return(burn_params)
      allow(V1::Logic::Secrets::BurnSecret).to receive(:new)
        .with(session, customer, burn_params, 'en')
        .and_return(logic)
      allow(logic).to receive(:raise_concerns)
      allow(logic).to receive(:process)
      allow(logic).to receive(:receipt).and_return(receipt)
    end

    context 'when secret is successfully burned' do
      before do
        allow(logic).to receive(:greenlighted).and_return(true)
        allow(described_class).to receive(:receipt_hsh).and_return({
          'metadata_key' => receipt_key,
          'state' => 'burned',
        })
      end

      it 'returns state and secret_shortkey as JSON' do
        expect(app).to receive(:json).with(
          hash_including(
            :state => hash_including('metadata_key' => receipt_key),
            :secret_shortkey => 'shortid123',
          ),
        )
        app.burn_secret
      end
    end

    context 'when secret cannot be burned (already consumed or missing)' do
      before do
        allow(logic).to receive(:greenlighted).and_return(false)
        allow(app).to receive(:secret_not_found_response)
      end

      it 'calls secret_not_found_response' do
        expect(app).to receive(:secret_not_found_response)
        app.burn_secret
      end
    end
  end

  # ===========================================================================
  # Rate limiting guard behavior [#2621]
  # ===========================================================================
  describe 'rate limiting guard' do
    # Rate-limited endpoints return early with V1 404+{message} shape
    # before instantiating any logic class.

    shared_examples 'rate-limited endpoint' do |method_name, event, max_const|
      context 'when rate-limited' do
        before do
          allow(app).to receive(:check_rate_limit!)
            .with(event, described_class.const_get(max_const))
            .and_return(:limited)
          allow(app).to receive(:error_response)
        end

        it 'returns early without calling logic' do
          # The logic class should never be instantiated
          expect(app).not_to receive(:json)
          app.send(method_name)
        end
      end

      context 'when not rate-limited' do
        before do
          allow(app).to receive(:check_rate_limit!)
            .with(event, described_class.const_get(max_const))
            .and_return(nil)
        end

        it 'proceeds to logic processing' do
          app.send(method_name)
        end
      end
    end

    describe '#share' do
      before do
        logic = instance_double(V1::Logic::Secrets::ConcealSecret)
        allow(V1::Logic::Secrets::ConcealSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(
          double('Secret', current_expiration: 3600, has_passphrase?: false))
        allow(logic).to receive(:receipt).and_return(double('Receipt', key: 'k'))
        allow(described_class).to receive(:receipt_hsh).and_return({})
        allow(app).to receive(:json)
      end

      include_examples 'rate-limited endpoint',
        :share, :create_secret, :V1_RATE_LIMIT_MAX_CREATES
    end

    describe '#generate' do
      before do
        logic = instance_double(V1::Logic::Secrets::GenerateSecret)
        allow(V1::Logic::Secrets::GenerateSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(
          double('Secret', current_expiration: 3600, has_passphrase?: false))
        receipt = double('Receipt', key: 'k', previewed!: nil)
        allow(logic).to receive(:receipt).and_return(receipt)
        allow(logic).to receive(:secret_value).and_return('gen')
        allow(described_class).to receive(:receipt_hsh).and_return({})
        allow(app).to receive(:json)
      end

      include_examples 'rate-limited endpoint',
        :generate, :create_secret, :V1_RATE_LIMIT_MAX_CREATES
    end

    describe '#create' do
      before do
        logic = instance_double(V1::Logic::Secrets::ConcealSecret)
        allow(V1::Logic::Secrets::ConcealSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:secret).and_return(
          double('Secret', current_expiration: 3600, has_passphrase?: false))
        allow(logic).to receive(:receipt).and_return(double('Receipt', key: 'k'))
        allow(described_class).to receive(:receipt_hsh).and_return({})
        allow(app).to receive(:json)
      end

      include_examples 'rate-limited endpoint',
        :create, :create_secret, :V1_RATE_LIMIT_MAX_CREATES
    end

    describe '#show_secret' do
      let(:secret_key) { 'test_rate_limit_key_abc' }

      before do
        allow(request).to receive(:params).and_return({'key' => secret_key})
        logic = instance_double(V1::Logic::Secrets::ShowSecret)
        allow(V1::Logic::Secrets::ShowSecret).to receive(:new).and_return(logic)
        allow(logic).to receive(:raise_concerns)
        allow(logic).to receive(:process)
        allow(logic).to receive(:show_secret).and_return(true)
        allow(logic).to receive(:secret_value).and_return('val')
        allow(logic).to receive(:share_domain).and_return('example.com')
        allow(app).to receive(:json)
      end

      include_examples 'rate-limited endpoint',
        :show_secret, :show_secret, :V1_RATE_LIMIT_MAX_READS
    end
  end
end
