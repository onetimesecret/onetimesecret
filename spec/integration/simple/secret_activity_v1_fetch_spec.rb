# frozen_string_literal: true

require_relative '../integration_spec_helper'

# Secret Activity for v1 link fetches through the full Rack stack:
# POST /api/v1/secret/:key always sends continue=true, so a fetch either
# reveals the secret or fails on the passphrase. A failed fetch records
# secret_get (third party) or previewed (the creator); a reveal records
# revealed only.
RSpec.describe 'Secret Activity for v1 secret link fetches', type: :integration do
  include_context 'auth_rack_test'

  let(:customer) do
    Onetime::Customer.new(email: "v1-fetch-#{SecureRandom.hex(6)}@example.com").tap do |account|
      account.update_passphrase('V1-Fetch-Activity1234!')
      account.verified = 'true'
      account.apitoken = SecureRandom.hex(20)
      account.save
    end
  end
  let(:workspace) { Onetime::Organization.create!("V1 fetch #{SecureRandom.hex(6)}", customer) }

  before(:all) { Onetime.boot! :test }

  before do
    clear_cookies
    header 'Authorization', nil
  end

  def json_post(path, params)
    post path, params, { 'HTTP_ACCEPT' => 'application/json' }
  end

  def sign_in
    basic_authorize customer.email, customer.apitoken
    header 'O-Organization-ID', workspace.objid
  end

  def sign_out
    header 'Authorization', nil
    header 'O-Organization-ID', nil
  end

  # A member's passphrase-protected secret, created over the v1 API.
  def share_with_passphrase
    sign_in
    json_post '/api/v1/share', { secret: 'v1 fetch activity', ttl: 3600, passphrase: 'right-phrase' }
    expect(last_response.status).to eq(200), last_response.body
    sign_out
    Onetime::Receipt.load(json_response.fetch('metadata_key'))
  end

  def fetch(receipt, passphrase)
    json_post "/api/v1/secret/#{receipt.secret_identifier}", { passphrase: passphrase }
  end

  def trail(kind)
    workspace.secret_activity_events_page(limit: 100).select { |event| event['kind'] == kind }
  end

  it "records a guest's wrong-passphrase fetch as secret_get with an anonymous actor" do
    receipt = share_with_passphrase
    expect(receipt.org_id).to eq(workspace.objid)

    fetch(receipt, 'wrong-phrase')
    expect(last_response.status).to eq(404), last_response.body

    events = trail('secret_get')
    expect(events.size).to eq(1)
    expect(events.first).to include('actor' => 'anonymous', 'receipt' => receipt.shortid)
    expect(events.first).not_to have_key('actor_id')
  end

  it "records the creator's wrong-passphrase fetch as previewed with the creator's id" do
    receipt = share_with_passphrase

    sign_in
    fetch(receipt, 'wrong-phrase')
    expect(last_response.status).to eq(404), last_response.body

    events = trail('previewed')
    expect(events.size).to eq(1)
    expect(events.first).to include('actor' => 'creator', 'actor_id' => customer.objid)
    expect(trail('secret_get')).to be_empty
  end

  it 'counts repeated wrong-passphrase fetches on one row and records the reveal separately' do
    receipt = share_with_passphrase

    2.times { fetch(receipt, 'wrong-phrase') }
    fetch(receipt, 'right-phrase')
    expect(last_response.status).to eq(200), last_response.body
    expect(json_response.fetch('value')).to eq('v1 fetch activity')

    gets = trail('secret_get')
    expect(gets.size).to eq(1)
    expect(gets.first['count']).to eq(2)
    expect(trail('revealed').size).to eq(1)
  end
end
