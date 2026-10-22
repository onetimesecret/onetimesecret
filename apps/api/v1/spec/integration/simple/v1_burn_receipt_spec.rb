# apps/api/v1/spec/integration/simple/v1_burn_receipt_spec.rb
#
# frozen_string_literal: true

# V1 burn and receipt responses through the full Rack stack (#4835).
#
# - The burn response (and its /private and /metadata aliases) describes the
#   receipt after the burn, not the instance the logic loaded before it, and
#   agrees with a follow-up fetch.
# - A terminal receipt never regains a secret key through the deprecated
#   secret_key field, which terminal transitions leave in place.
# - The receipt URLs are built from the receipt identifier, not the
#   deprecated key field (which left every URL ending in "/receipt/").
# - The V1 serializer applies the same provenance gate as V2/V3: an incoming
#   receipt does not hand its holder the secret key.

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'V1 burn and receipt responses (#4835)', type: :integration do
  include Rack::Test::Methods

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

  # @return [Array(String, String)] the receipt and secret identifiers
  def create_secret
    post '/api/v1/share', { secret: 'v1 burn response secret', ttl: 3600 }
    expect(last_response.status).to eq(200), last_response.body
    body = JSON.parse(last_response.body)
    [body['metadata_key'], body['secret_key']]
  end

  def json_body
    JSON.parse(last_response.body)
  end

  %w[receipt private metadata].each do |prefix|
    describe "POST /api/v1/#{prefix}/:key/burn" do
      it 'reports the burned receipt, destroys the secret, and agrees with a follow-up fetch' do
        metadata_key, secret_key = create_secret

        post "/api/v1/#{prefix}/#{metadata_key}/burn", { continue: 'true' }

        expect(last_response.status).to eq(200), last_response.body
        state = json_body['state']
        expect(state['state']).to eq('burned')
        expect(state['secret_key']).to eq('')
        expect(state['secret_identifier']).to eq('')
        expect(state['metadata_url']).to end_with("/receipt/#{metadata_key}")
        expect(last_response.body).not_to include(secret_key)

        expect(Onetime::Secret.load(secret_key)).to be_nil
        post "/api/v1/secret/#{secret_key}", {}
        expect(last_response.status).to eq(404)

        get "/api/v1/#{prefix}/#{metadata_key}"
        expect(last_response.status).to eq(200), last_response.body
        fetched = json_body
        expect(fetched['state']).to eq(state['state'])
        expect(fetched['secret_key']).to eq(state['secret_key'])
        expect(fetched['secret_identifier']).to eq(state['secret_identifier'])
      end
    end
  end

  # V1 maps 'previewed' to 'viewed'; the stale instance reported that
  # instead of 'burned'.
  it 'reports burned for a receipt that was previewed before the burn' do
    metadata_key, = create_secret
    receipt       = Onetime::Receipt.load(metadata_key)
    receipt.state = 'previewed'
    receipt.save

    get "/api/v1/receipt/#{metadata_key}"
    expect(json_body['state']).to eq('viewed')

    post "/api/v1/receipt/#{metadata_key}/burn", { continue: 'true' }

    expect(last_response.status).to eq(200), last_response.body
    expect(json_body.dig('state', 'state')).to eq('burned')
    expect(json_body.dig('state', 'secret_key')).to eq('')
  end

  # burned! clears secret_identifier but leaves the deprecated secret_key
  # field, so the serializer's legacy fallback would hand the burned receipt
  # its old key back.
  it 'does not restore a populated legacy secret_key field on the burned receipt' do
    metadata_key, secret_key = create_secret
    receipt            = Onetime::Receipt.load(metadata_key)
    receipt.secret_key = secret_key
    receipt.save
    expect(Onetime::Receipt.load(metadata_key).secret_key).to eq(secret_key)

    post "/api/v1/receipt/#{metadata_key}/burn", { continue: 'true' }

    expect(last_response.status).to eq(200), last_response.body
    expect(json_body.dig('state', 'state')).to eq('burned')
    expect(json_body.dig('state', 'secret_key')).to eq('')
    expect(json_body.dig('state', 'secret_identifier')).to eq('')
    expect(last_response.body).not_to include(secret_key)
    # The field is still populated: the serializer, not a cleanup write, is
    # what keeps it out of the response.
    expect(Onetime::Receipt.load(metadata_key).secret_key).to eq(secret_key)
  end

  describe 'GET /api/v1/receipt/:key' do
    it 'builds metadata_url and receipt_url from the receipt identifier' do
      metadata_key, = create_secret

      get "/api/v1/receipt/#{metadata_key}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['metadata_url']).to end_with("/receipt/#{metadata_key}")
      expect(json_body['receipt_url']).to eq(json_body['metadata_url'])
    end

    it 'returns the secret key for a live standard receipt' do
      metadata_key, secret_key = create_secret

      get "/api/v1/receipt/#{metadata_key}"

      expect(json_body['secret_key']).to eq(secret_key)
    end

    # The guest who submits an incoming secret holds the receipt identifier.
    # V2/V3 withhold the secret key from it (Receipt#shows_share_link?); V1
    # must too, or the guest could spend the recipient's one view.
    it 'withholds the secret key of an incoming receipt' do
      receipt, secret = Onetime::Receipt.spawn_pair(nil, 3600, 'incoming secret value')
      receipt.source = 'incoming'
      receipt.save

      get "/api/v1/receipt/#{receipt.identifier}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['secret_key']).to eq('')
      expect(json_body['secret_identifier']).to eq('')
      expect(last_response.body).not_to include(secret.identifier)
      expect(Onetime::Secret.load(secret.identifier)&.viewable?).to be true
    end
  end
end
