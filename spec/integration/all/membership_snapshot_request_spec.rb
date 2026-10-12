# spec/integration/all/membership_snapshot_request_spec.rb
#
# frozen_string_literal: true

# One request reads the customer's membership list once. The auth strategy's
# organization load, the bootstrap serializer (is_current_user_default,
# current_user_role), the organizations list and the session commit
# (Sessions::TrackMetadata) all answer from the request's
# Onetime::MembershipSnapshot, which Middleware::MembershipSnapshotContext
# opens for the request. The customer is loaded more than once along the
# way; hydrating a record must not drop the snapshot.
#
# Run: tests/lanes/run full-sqlite --only spec/integration/all/membership_snapshot_request_spec.rb
require 'spec_helper'
require 'rack/test'
require_relative '../integration_spec_helper'

RSpec.describe 'Membership reads per request', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    require 'onetime'
    Onetime.boot! :test
    Onetime::Application::Registry.prepare_application_registry
  end

  def app
    @app ||= Onetime::Application::Registry.generate_rack_url_map
  end

  let(:now) { Familia.now.to_i }
  let(:suffix) { "#{now}_#{SecureRandom.hex(4)}" }

  def create_customer(label)
    cust          = Onetime::Customer.create!(email: "snapshot-#{label}-#{suffix}@example.com")
    cust.role     = 'customer'
    cust.verified = 'true'
    cust.save
    cust
  end

  def signed_in_as(user)
    env 'rack.session', {
      'external_id' => user.extid,
      'authenticated' => true,
      Onetime::SessionSurface::KEY => Onetime::SessionSurface::CANONICAL,
      'authenticated_at' => now,
      'role' => user.role,
    }
  end

  # Membership-list reads, by the customer they were made for.
  def count_list_reads
    reads = Hash.new(0)
    allow_any_instance_of(Onetime::Customer).to receive(:organization_instances).and_wrap_original do |m, *args|
      reads[m.receiver.objid] += 1
      m.call(*args)
    end
    reads
  end

  before do
    @cust    = create_customer('member')
    @other   = create_customer('owner')
    @owned   = Onetime::Organization.create!("Owned #{suffix}", @cust, is_default: true)
    @foreign = Onetime::Organization.create!("Foreign #{suffix}", @other, is_default: true)
    Onetime::OrganizationMembership.ensure_membership(@foreign, @cust, role: 'member')
    signed_in_as(@cust)
  end

  after do
    [@owned, @foreign].each { |org| org&.destroy! rescue nil } # rubocop:disable Style/RescueModifier
    [@cust, @other].each { |cust| cust&.destroy! rescue nil } # rubocop:disable Style/RescueModifier
  end

  it 'reads the list once for a page load that falls back to the owned default' do
    header 'Accept', 'text/html'
    reads = count_list_reads

    get '/dashboard'

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include(@owned.objid)
    expect(last_response.body).to include('"is_current_user_default":true')
    expect(reads).to eq(@cust.objid => 1)
  end

  it 'reads the list once for a page load on the preferred, joined workspace' do
    @cust.default_org_id!(@foreign.objid)
    header 'Accept', 'text/html'
    reads = count_list_reads

    get '/dashboard'

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include(@foreign.objid)
    expect(last_response.body).to include('"is_current_user_default":true')
    expect(last_response.body).to include('"current_user_role":"member"')
    expect(reads).to eq(@cust.objid => 1)
  end

  it 'reads the list once for the organizations list' do
    header 'Accept', 'application/json'
    reads = count_list_reads

    get '/api/organizations'

    expect(last_response.status).to eq(200)
    records = JSON.parse(last_response.body)['records']
    expect(records.map { |r| r['objid'] }).to contain_exactly(@owned.objid, @foreign.objid)
    expect(records.find { |r| r['objid'] == @owned.objid }['is_current_user_default']).to be(true)
    expect(reads).to eq(@cust.objid => 1)
  end

  it 'leaves no snapshot open between requests' do
    header 'Accept', 'text/html'
    get '/dashboard'

    expect(Onetime::MembershipSnapshot.open?).to be(false)
  end
end
