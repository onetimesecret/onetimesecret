# spec/integration/simple/reveal_notice_paths_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration — the owner's reveal notice on every reveal route
# =============================================================================
#
# The secret_revealed email used to go out only from V3 RevealSecret. A v1
# reveal, a v2 reveal, and a v2/v3 ShowSecret with continue=true consumed the
# secret without telling an owner who had opted in. The notice is now sent
# from Secret#consume_after_reveal!, which every route below reaches, once
# per reveal and only from the caller that won the receipt's transition.
#
#   POST /api/v1/secret/:key                    V1 ShowSecret
#   POST /api/v2/guest/secret/:id/reveal        V2 RevealSecret
#   POST /api/v3/guest/secret/:id/reveal        V3 RevealSecret
#   GET  /api/v2/guest/secret/:id?continue=true V2 ShowSecret
#   GET  /api/v3/guest/secret/:id?continue=true V3 ShowSecret
#
# Each route also takes the receipt off the expiration timeline. The model-
# level cases (race loser, verification secrets, failures, locale, domain_id)
# are in spec/unit/onetime/models/secret_reveal_notice_spec.rb.
#
# RUN:
#   tests/lanes/run simple --only spec/integration/simple/reveal_notice_paths_spec.rb
#
# =============================================================================

require_relative '../integration_spec_helper'

RSpec.describe 'Owner reveal notice on every reveal route', type: :integration do
  include Rack::Test::Methods

  def app
    # Memoize: repeated generate_rack_url_map calls corrupt middleware state.
    @app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      Onetime::Application::Registry.generate_rack_url_map
    end
  end

  before(:all) do
    require 'onetime'
    require 'onetime/config'
    Onetime.boot! :test
    require 'onetime/application/registry'

    app
  end

  # Above min_warning_ttl (48h), so the receipt starts on the timeline.
  let(:lifespan) { 3 * 24 * 3600 }

  let(:owner) do
    Onetime::Customer.new(email: "reveal-route-#{SecureRandom.hex(8)}@integration-test.example.com").tap do |cust|
      cust.notify_on_reveal = 'true'
      cust.verified         = 'true'
      cust.save
    end
  end

  let(:sent) { [] }

  before do
    skip 'requires simple auth mode' if Onetime.auth_config.full_enabled?

    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email) do |template, data, **options|
      sent << [template, data, options]
      true
    end
  end

  after do
    owner.destroy! if owner.exists?
  rescue StandardError => ex
    warn "[reveal-notice routes spec] owner cleanup failed: #{ex.class}"
  end

  def notices
    sent.select { |template, _data, _options| template == :secret_revealed }
  end

  # A fresh anonymous session: a session cookie and a CSRF token.
  def anonymous_visit
    clear_cookies
    header 'Content-Type', nil
    header 'Accept', 'application/json'
    get '/'
    token = last_response.headers['X-CSRF-Token']
    raise "CSRF setup failed: GET / returned #{last_response.status} with no X-CSRF-Token header" if token.to_s.empty?

    token
  end

  def json_post(path, token, body = {})
    header 'Content-Type', 'application/json'
    header 'X-CSRF-Token', token
    post path, JSON.generate(body)
  end

  def on_timeline?(receipt)
    !Onetime::Receipt.expiration_timeline.score(receipt.identifier).nil?
  end

  reveal_routes = {
    'POST /api/v1/secret/:key' => ->(id, token) {
      header 'Content-Type', 'application/x-www-form-urlencoded'
      header 'X-CSRF-Token', token
      post "/api/v1/secret/#{id}"
    },
    'POST /api/v2/guest/secret/:id/reveal' => ->(id, token) {
      json_post("/api/v2/guest/secret/#{id}/reveal", token, continue: true)
    },
    'POST /api/v3/guest/secret/:id/reveal' => ->(id, token) {
      json_post("/api/v3/guest/secret/#{id}/reveal", token, continue: true)
    },
    'GET /api/v2/guest/secret/:id?continue=true' => ->(id, _token) {
      get "/api/v2/guest/secret/#{id}", continue: 'true'
    },
    'GET /api/v3/guest/secret/:id?continue=true' => ->(id, _token) {
      get "/api/v3/guest/secret/#{id}", continue: 'true'
    },
  }.freeze

  reveal_routes.each do |route, reveal|
    it "sends exactly one notice, short id only, through #{route}" do
      receipt, secret = Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'route notice fixture')
      expect(on_timeline?(receipt)).to be(true)

      token = anonymous_visit
      instance_exec(secret.identifier, token, &reveal)

      expect(last_response.status).to eq(200), "#{route}: #{last_response.status} #{last_response.body}"
      expect(last_response.body).to include('route notice fixture')

      expect(notices.size).to eq(1), "#{route}: #{sent.inspect}"
      _template, data, options = notices.first
      expect(data.keys).to contain_exactly(:recipient, :secret_shortid, :revealed_at, :locale)
      expect(data).to include(recipient: owner.email, secret_shortid: secret.shortid, locale: OT.default_locale)
      expect(options).to eq(domain_id: nil)
      expect(data.to_s).not_to include(secret.identifier, receipt.identifier, 'route notice fixture')

      expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
      expect(on_timeline?(receipt)).to be(false)
    end
  end

  # Mail goes only to a verified account (Customer#verified?). An opted-in
  # owner whose account is not verified gets nothing; the reveal itself
  # still succeeds.
  context 'when the opted-in owner is not verified' do
    let(:owner) do
      Onetime::Customer.new(email: "reveal-route-unv-#{SecureRandom.hex(8)}@integration-test.example.com").tap do |cust|
        cust.notify_on_reveal = 'true'
        cust.verified         = 'false'
        cust.save
      end
    end

    reveal_routes.slice('POST /api/v1/secret/:key', 'POST /api/v3/guest/secret/:id/reveal').each do |route, reveal|
      it "sends no notice and still reveals through #{route}" do
        expect(owner.notify_on_reveal?).to be(true)
        expect(owner.verified?).to be(false)
        receipt, secret = Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'route notice fixture')

        token = anonymous_visit
        instance_exec(secret.identifier, token, &reveal)

        expect(last_response.status).to eq(200), "#{route}: #{last_response.status} #{last_response.body}"
        expect(last_response.body).to include('route notice fixture')
        expect(notices).to be_empty, "#{route}: #{sent.inspect}"
        expect(Onetime::Secret.load(secret.identifier)).to be_nil
        expect(Onetime::Receipt.load(receipt.identifier).state).to eq('revealed')
        expect(on_timeline?(receipt)).to be(false)
      end
    end
  end

  {
    'GET /api/v2/guest/secret/:id' => ->(id) { get "/api/v2/guest/secret/#{id}" },
    'GET /api/v3/guest/secret/:id' => ->(id) { get "/api/v3/guest/secret/#{id}" },
  }.each do |route, show|
    it "sends nothing for a metadata-only #{route} (no continue)" do
      receipt, secret = Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'route notice fixture')

      anonymous_visit
      instance_exec(secret.identifier, &show)

      expect(last_response.status).to eq(200), "#{route}: #{last_response.status} #{last_response.body}"
      expect(notices).to be_empty
      expect(on_timeline?(receipt)).to be(true)
    ensure
      Onetime::Receipt.expiration_timeline.remove_element(receipt.identifier) if receipt
    end
  end

  # The burn routes reach Secret#burned!, which takes the receipt off the
  # timeline and sends no reveal notice.
  it 'takes the receipt off the timeline on burn and sends no notice' do
    receipt, _secret = Onetime::Receipt.spawn_pair(owner.objid, lifespan, 'route notice fixture')
    expect(on_timeline?(receipt)).to be(true)

    token = anonymous_visit
    json_post("/api/v3/guest/receipt/#{receipt.identifier}/burn", token, continue: true)

    expect(last_response.status).to eq(200), "burn: #{last_response.status} #{last_response.body}"
    expect(Onetime::Receipt.load(receipt.identifier).state).to eq('burned')
    expect(on_timeline?(receipt)).to be(false)
    expect(notices).to be_empty
  end
end
