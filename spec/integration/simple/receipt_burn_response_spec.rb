# spec/integration/simple/receipt_burn_response_spec.rb
#
# frozen_string_literal: true

# The V2 and V3 burn endpoints report the receipt after the burn (#4835).
#
# BurnSecret loaded the receipt before Secret#burned! cascaded the burn
# through a separate, freshly loaded instance, then serialized its own stale
# copy: state "new", is_burned false, and a share link to the secret it had
# just destroyed. These examples drive every V2/V3 burn route through the full
# Rack stack and check the response against the persisted receipt, a
# follow-up fetch, and the secret's absence. V1 has its own shape and is
# covered in apps/api/v1/spec/integration/simple/v1_burn_receipt_spec.rb.

require_relative '../integration_spec_helper'

RSpec.describe 'Burn responses report the post-burn receipt (#4835)', type: :integration do
  include_context 'auth_rack_test'

  let(:app) do
    @receipt_burn_response_app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  let(:password) { 'Burn-Response1234!' }

  before(:all) do
    Onetime.boot! :test
  end

  before do
    clear_cookies
  end

  # Anonymous JSON POST: an /api/ request with no authenticated session
  # needs no CSRF token.
  def anonymous_post(path, payload)
    post path,
      payload.to_json,
      { 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json' }
  end

  # @return [Array(String, String)] the receipt and secret identifiers
  def receipt_and_secret_ids
    expect(last_response.status).to eq(200), last_response.body
    record = JSON.parse(last_response.body)['record']
    [record.dig('receipt', 'identifier'), record.dig('secret', 'identifier')]
  end

  def sign_in!
    customer = Onetime::Customer.new(email: "burn-response-#{SecureRandom.hex(8)}@example.com")
    customer.update_passphrase(password)
    customer.verified = 'true'
    customer.save

    post_json '/auth/login', { login: customer.email, password: password }
    expect(last_response.status).to eq(200), last_response.body
  end

  # Checks the burn response in last_response against the burn that happened:
  # the post-burn state and flags, no link or key for the destroyed secret,
  # the secret gone, and the persisted receipt burned.
  #
  # @return [Hash] the response record, for comparison with a fetch
  def expect_post_burn_receipt(receipt_id:, secret_id:)
    expect(last_response.status).to eq(200), last_response.body
    body   = JSON.parse(last_response.body)
    record = body['record']

    expect(body['success']).to be true
    expect(record['identifier']).to eq(receipt_id)
    expect(record['state']).to eq('burned')
    expect(record['is_burned']).to be true
    expect(record['is_destroyed']).to be true
    expect(record['burned']).to be_a(Integer)
    expect(record['share_path']).to be_nil
    expect(record['share_url']).to be_nil
    expect(record).not_to have_key('secret_identifier')
    expect(last_response.body).not_to include(secret_id)

    expect(Onetime::Secret.load(secret_id)).to be_nil
    expect(Onetime::Receipt.load(receipt_id).state).to eq('burned')

    record
  end

  def expect_fetch_to_agree(fetched_response, burned_record)
    expect(fetched_response.status).to eq(200), fetched_response.body
    fetched = JSON.parse(fetched_response.body)['record']

    %w[state is_burned is_destroyed burned share_path share_url].each do |field|
      expect(fetched[field]).to eq(burned_record[field]),
        "#{field}: fetch=#{fetched[field].inspect} burn=#{burned_record[field].inspect}"
    end
    expect(fetched).not_to have_key('secret_identifier')
  end

  {
    'POST /api/v2/receipt/:identifier/burn' => ['/api/v2/receipt/%s/burn', '/api/v2/receipt/%s'],
    'POST /api/v2/private/:identifier/burn' => ['/api/v2/private/%s/burn', '/api/v2/private/%s'],
    'POST /api/v2/guest/receipt/:identifier/burn' => ['/api/v2/guest/receipt/%s/burn', '/api/v2/guest/receipt/%s'],
  }.each do |label, (burn_path, show_path)|
    describe label do
      it 'reports the burned receipt and agrees with a follow-up fetch' do
        anonymous_post '/api/v2/secret/conceal', { secret: { secret: 'v2 burn response', ttl: 3600 } }
        receipt_id, secret_id = receipt_and_secret_ids

        anonymous_post format(burn_path, receipt_id), { continue: true }
        burned = expect_post_burn_receipt(receipt_id: receipt_id, secret_id: secret_id)

        get format(show_path, receipt_id), {}, { 'HTTP_ACCEPT' => 'application/json' }
        expect_fetch_to_agree(last_response, burned)
      end
    end
  end

  describe 'POST /api/v3/guest/receipt/:identifier/burn' do
    it 'reports the burned receipt and agrees with a follow-up fetch' do
      anonymous_post '/api/v3/guest/secret/conceal', { secret: { secret: 'v3 guest burn response', ttl: 3600 } }
      receipt_id, secret_id = receipt_and_secret_ids

      anonymous_post "/api/v3/guest/receipt/#{receipt_id}/burn", { continue: true }
      burned = expect_post_burn_receipt(receipt_id: receipt_id, secret_id: secret_id)

      get "/api/v3/guest/receipt/#{receipt_id}", {}, { 'HTTP_ACCEPT' => 'application/json' }
      expect_fetch_to_agree(last_response, burned)
    end
  end

  describe 'POST /api/v3/receipt/:identifier/burn (session-authenticated)' do
    before do
      skip 'requires simple auth mode' unless Onetime.auth_config.simple_enabled?
    end

    it 'reports the burned receipt and agrees with a follow-up fetch' do
      sign_in!

      post_json '/api/v3/secret/conceal', { secret: { secret: 'v3 session burn response', ttl: 3600 } }
      receipt_id, secret_id = receipt_and_secret_ids

      post_json "/api/v3/receipt/#{receipt_id}/burn", { continue: true }
      burned = expect_post_burn_receipt(receipt_id: receipt_id, secret_id: secret_id)

      get_json "/api/v3/receipt/#{receipt_id}"
      expect_fetch_to_agree(last_response, burned)
    end
  end

  # A burn that does not commit (continue=false) leaves the secret in place.
  # Its response and a follow-up fetch include secret_identifier under the
  # same rule (Receipt#offers_secret?): only while the receipt still offers
  # the secret. share_url names the secret in both either way.
  {
    'POST /api/v2/receipt/:identifier/burn' => ['/api/v2/secret/conceal', '/api/v2/receipt/%s'],
    'POST /api/v3/guest/receipt/:identifier/burn' => ['/api/v3/guest/secret/conceal', '/api/v3/guest/receipt/%s'],
  }.each do |label, (conceal_path, show_path)|
    describe "#{label} with continue=false" do
      # @return [Array(Hash, Hash)] the burn and fetch records
      def uncommitted_burn_and_fetch(show_path, receipt_id)
        anonymous_post format("#{show_path}/burn", receipt_id), { continue: false }
        expect(last_response.status).to eq(200), last_response.body
        burned = JSON.parse(last_response.body)['record']

        get format(show_path, receipt_id), {}, { 'HTTP_ACCEPT' => 'application/json' }
        expect(last_response.status).to eq(200), last_response.body
        fetched = JSON.parse(last_response.body)['record']

        [burned, fetched]
      end

      it 'includes secret_identifier in both for a secret without a passphrase' do
        anonymous_post conceal_path, { secret: { secret: 'uncommitted plain', ttl: 3600 } }
        receipt_id, secret_id = receipt_and_secret_ids

        burned, fetched = uncommitted_burn_and_fetch(show_path, receipt_id)

        expect(burned['secret_identifier']).to eq(secret_id)
        expect(fetched['secret_identifier']).to eq(secret_id)
        expect(burned['share_url']).to eq(fetched['share_url'])
        expect(Onetime::Secret.load(secret_id)&.viewable?).to be true
      end

      it 'omits secret_identifier from both for a passphrase-protected secret' do
        anonymous_post conceal_path,
          { secret: { secret: 'uncommitted passphrase', ttl: 3600, passphrase: 'correct horse battery' } }
        receipt_id, secret_id = receipt_and_secret_ids

        burned, fetched = uncommitted_burn_and_fetch(show_path, receipt_id)

        expect(burned).not_to have_key('secret_identifier')
        expect(fetched).not_to have_key('secret_identifier')
        expect(burned['share_url']).to end_with("/secret/#{secret_id}")
        expect(burned['share_url']).to eq(fetched['share_url'])
        expect(Onetime::Secret.load(secret_id)&.viewable?).to be true
      end

      it 'omits secret_identifier from both for a previewed receipt' do
        anonymous_post conceal_path, { secret: { secret: 'uncommitted previewed', ttl: 3600 } }
        receipt_id, secret_id = receipt_and_secret_ids
        receipt       = Onetime::Receipt.load(receipt_id)
        receipt.state = 'previewed'
        receipt.save

        burned, fetched = uncommitted_burn_and_fetch(show_path, receipt_id)

        expect(burned).not_to have_key('secret_identifier')
        expect(fetched).not_to have_key('secret_identifier')
        expect(burned['share_url']).to end_with("/secret/#{secret_id}")
        expect(burned['share_url']).to eq(fetched['share_url'])
      end
    end
  end
end
