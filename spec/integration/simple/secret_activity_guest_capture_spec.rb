# frozen_string_literal: true

require_relative '../integration_spec_helper'

# Secret Activity capture for a guest creating a secret on an organization's
# custom domain, through the full Rack stack: domain strategy middleware,
# the v1 controller and V1 ConcealSecret. The logic-level cases (member
# creation, archived organization, link-pool host, v2) are in
# spec/api/secret_activity_creation_capture_spec.rb.
RSpec.describe 'Secret Activity capture for a guest on a custom domain', type: :integration do
  include_context 'auth_rack_test'

  let(:run_id) { SecureRandom.hex(6) }
  let(:owner) { Onetime::Customer.create!(email: "guest-capture-#{run_id}@example.com") }
  let(:organization) { Onetime::Organization.create!("Guest capture #{run_id}", owner) }
  let(:pool_host) { 'links.pool-example.com' }
  let(:domain) do
    Onetime::CustomDomain.new(display_domain: "guest-capture-#{run_id}.tenant-example.com",
      org_id: organization.objid).tap do |record|
      record.ownership_verified   = true
      record.verified_by_override = true
      record.verified             = true
      record.save
      Onetime::CustomDomain.display_domain_index.put(record.display_domain, record.identifier)
      organization.domains.add(record.objid)
      Onetime::CustomDomain::HomepageConfig.create!(domain_id: record.identifier, enabled: true,
        secrets_mode: 'classic')
    end
  end

  before(:all) { Onetime.boot! :test }

  around do |example|
    app
    original_config   = OT.conf.get('features.domains')
    original_features = Onetime::Runtime.features
    begin
      OT.conf.get('features')['domains'] = original_config.merge('enabled' => true,
        'default' => 'canonical.example.com', 'link_domains' => [pool_host])
      Onetime::Runtime.features = original_features.with(domains_enabled: true)
      Onetime::Middleware::DomainStrategy.initialize_from_config
      example.run
    ensure
      OT.conf.get('features')['domains'] = original_config
      Onetime::Runtime.features          = original_features
      Onetime::Middleware::DomainStrategy.initialize_from_config
    end
  end

  before do
    clear_cookies
    header 'Authorization', nil
  end

  def trail
    organization.secret_activity_events_page
  end

  def guest_share(host = domain.display_domain)
    header 'Host', host
    post '/api/v1/share', { secret: 'guest capture', ttl: 3600 }, { 'HTTP_ACCEPT' => 'application/json' }
    expect(last_response.status).to eq(200), last_response.body
    Onetime::Receipt.load(json_response.fetch('metadata_key'))
  end

  it "stamps a v1 guest receipt with the domain's organization and records created" do
    receipt = guest_share

    expect(receipt.org_id).to eq(organization.objid)
    expect(receipt.domain_id).to eq(domain.objid)
    expect(domain.receipts.score(receipt)).to be_within(60).of(Familia.now.to_f)
    expect(organization.receipts.member?(receipt)).to be(false)

    created = trail.select { |event| event['kind'] == 'created' }
    expect(created.size).to eq(1)
    expect(created.first).to include('actor' => 'anonymous', 'receipt' => receipt.shortid)
    expect(created.first).not_to have_key('actor_id')
  end

  it "sends the guest secret's reveal to the same trail" do
    receipt = guest_share

    post "/api/v1/secret/#{receipt.secret_identifier}", { continue: 'true' },
      { 'HTTP_ACCEPT' => 'application/json' }
    expect(last_response.status).to eq(200), last_response.body

    kinds = trail.map { |event| event['kind'] }
    expect(kinds).to include('created', 'revealed')
    expect(kinds).not_to include('secret_get')
  end

  it 'stamps nothing for a guest on an operator link-pool host' do
    expect(Onetime::Middleware::DomainStrategy.link_pool_host?(pool_host)).to be(true)
    domain # registered, so a stamp would have an organization to come from

    receipt = guest_share(pool_host)

    expect(receipt.org_id.to_s).to be_empty
    expect(receipt.domain_id.to_s).to be_empty
    expect(trail).to be_empty
  end
end
