# apps/api/v1/spec/integration/simple/v1_head_boundary_spec.rb
#
# frozen_string_literal: true

# HEAD on the V1 receipt routes through the full Rack stack.
#
# Otto answers HEAD with the matching GET route. On GET /receipt/:key (and
# the /private and /metadata aliases) that runs V1 ShowReceipt, which spends
# the creator's one-time display of a generated value
# (Receipt#claim_secret_value_display!) and records the one-time
# 'receipt_viewed' event. A link preview, scanner or probe sending HEAD
# must not spend either. V2 and V3 refuse these HEAD requests the same way
# (spec/integration/simple/api_v3_http_boundary_spec.rb).

require_relative File.join(Onetime::HOME, 'spec', 'integration', 'integration_spec_helper')

RSpec.describe 'V1 HEAD on one-time receipt reads', :aggregate_failures, type: :integration do
  include Rack::Test::Methods

  before(:all) do
    Onetime.boot! :test
  end

  def app
    @app ||= begin
      Onetime::Application::Registry.reset!
      Onetime::Application::Registry.prepare_application_registry
      rack_app = Onetime::Application::Registry.generate_rack_url_map
      # Otto skips its production lazy freeze under RSpec. Exercise the frozen
      # state, as the V2/V3 HEAD boundary spec does.
      v1_router.freeze_configuration!
      rack_app
    end
  end

  def v1_router
    Onetime::Application::Registry.application_instances.fetch(V1::Application).router
  end

  def json_body
    JSON.parse(last_response.body)
  end

  # @return [Array(String, String, String)] the receipt identifier, the
  #   secret identifier and the generated value
  def generate_pair
    post '/api/v1/generate', { ttl: 3600 }
    expect(last_response.status).to eq(200), last_response.body
    body = json_body
    expect(body['value'].to_s).not_to be_empty
    [body['metadata_key'], body['secret_key'], body['value']]
  end

  # Compare stored records, not only response fields.
  def secret_storage
    [Onetime::Secret, Onetime::Receipt].to_h do |model|
      keys = model.dbclient.scan_each(match: "#{model.prefix}:*").to_a.sort
      [model.name, keys.to_h { |key| [key, model.dbclient.dump(key)] }]
    end
  end

  %w[receipt private metadata].each do |prefix|
    it "refuses HEAD /api/v1/#{prefix}/:key without spending the creator's one-time display" do
      metadata_key, secret_key, value = generate_pair
      before_storage                  = secret_storage

      2.times do
        head "/api/v1/#{prefix}/#{metadata_key}"

        expect(last_response.status).to eq(405)
        expect(last_response.headers['allow'].to_s.split(/,\s*/)).to contain_exactly('GET', 'POST')
        expect(last_response.body).to eq('')
      end

      expect(v1_router.frozen_configuration?).to be(true)
      expect(v1_router.routes).not_to have_key(:HEAD)
      expect(secret_storage).to eq(before_storage)
      expect(Onetime::Receipt.load(metadata_key).secret_value_shown_at.to_s).to be_empty
      expect(Onetime::Secret.load(secret_key)&.viewable?).to be(true)

      get "/api/v1/#{prefix}/#{metadata_key}"

      expect(last_response.status).to eq(200), last_response.body
      expect(json_body['value']).to eq(value)
      expect(Onetime::Receipt.load(metadata_key).secret_value_shown_at.to_s).not_to be_empty
    end
  end

  it 'keeps HEAD on the read-only V1 routes available and bodyless' do
    generate_pair
    before_storage = secret_storage

    %w[/api/v1/status /api/v1/receipt/recent /api/v1/private/recent /api/v1/metadata/recent].each do |path|
      get path
      get_status = last_response.status
      head path
      expect(last_response.status).to eq(get_status), "#{path}: #{last_response.status}"
      expect(last_response.body).to eq('')
    end

    expect(secret_storage).to eq(before_storage)
  end
end
