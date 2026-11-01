# apps/api/v1/spec/integration/simple/v1_burn_receipt_spec.rb
#
# frozen_string_literal: true

# V1 burn and receipt responses through the full Rack stack (#4835).
#
# - The burn response (and its /private and /metadata aliases) describes the
#   receipt after the burn, not the instance the logic loaded before it, and
#   agrees with a follow-up fetch.
# - A terminal receipt never regains a secret key through a stale secret_key
#   hash field (the pre-v0.24 name, no longer declared on the model).
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

  # A receipt written before the rename to secret_identifier can still carry
  # a secret_key hash field. The model no longer declares it, so the value
  # never reaches to_h, and the serializer's old fallback to it is gone.
  it 'does not restore a stale secret_key hash field on the burned receipt' do
    metadata_key, secret_key = create_secret
    receipt = Onetime::Receipt.load(metadata_key)
    Onetime::Receipt.dbclient.hset(receipt.dbkey, 'secret_key', secret_key)
    expect(Onetime::Receipt.load(metadata_key).to_h).not_to have_key('secret_key')

    post "/api/v1/receipt/#{metadata_key}/burn", { continue: 'true' }

    expect(last_response.status).to eq(200), last_response.body
    expect(json_body.dig('state', 'state')).to eq('burned')
    expect(json_body.dig('state', 'secret_key')).to eq('')
    expect(json_body.dig('state', 'secret_identifier')).to eq('')
    expect(last_response.body).not_to include(secret_key)

    get "/api/v1/receipt/#{metadata_key}"
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['secret_key']).to eq('')
    expect(last_response.body).not_to include(secret_key)

    # The stale field is still in the hash after the burn and the GET: no
    # write touches it, and no read sees it.
    expect(Onetime::Receipt.dbclient.hget(receipt.dbkey, 'secret_key')).to eq(secret_key)
  end

  describe 'GET /api/v1/receipt/:key' do
    it 'builds metadata_url and receipt_url from the receipt identifier' do
      metadata_key, = create_secret

      get "/api/v1/receipt/#{metadata_key}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['metadata_url']).to end_with("/receipt/#{metadata_key}")
      expect(json_body['receipt_url']).to eq(json_body['metadata_url'])
    end

    # The GET used to clear the old field on the way to orphaned!; the
    # transition's save now leaves a stale hash field where it is.
    it 'reports an orphaned receipt without a key and leaves a stale secret_key field alone' do
      metadata_key, secret_key = create_secret
      receipt = Onetime::Receipt.load(metadata_key)
      Onetime::Receipt.dbclient.hset(receipt.dbkey, 'secret_key', secret_key)
      Onetime::Secret.dbclient.del(Onetime::Secret.load(secret_key).dbkey)

      get "/api/v1/receipt/#{metadata_key}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['state']).to eq('orphaned')
      expect(json_body['secret_key']).to eq('')
      expect(last_response.body).not_to include(secret_key)

      stored = Onetime::Receipt.load(metadata_key)
      expect(stored.state).to eq('orphaned')
      expect(stored.to_h).not_to have_key('secret_key')
      expect(Onetime::Receipt.dbclient.hget(receipt.dbkey, 'secret_key')).to eq(secret_key)
    end

    # Receipt#load_secret resolves the secret by secret_identifier alone, so
    # a key found only under the old hash field names a secret the receipt
    # cannot load. The GET used to hide it with an in-memory clear before
    # orphaned!; the model no longer sees the field at all.
    it 'returns no key for a live receipt whose key is only in a stale secret_key field' do
      metadata_key, secret_key  = create_secret
      receipt                   = Onetime::Receipt.load(metadata_key)
      receipt.secret_identifier = ''
      receipt.save
      Onetime::Receipt.dbclient.hset(receipt.dbkey, 'secret_key', secret_key)

      get "/api/v1/receipt/#{metadata_key}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['secret_key']).to eq('')
      expect(json_body['secret_identifier']).to eq('')
      expect(last_response.body).not_to include(secret_key)
      expect(Onetime::Receipt.dbclient.hget(receipt.dbkey, 'secret_key')).to eq(secret_key)
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
