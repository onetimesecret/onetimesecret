# frozen_string_literal: true

require 'spec_helper'
require_relative '../../apps/api/v1/application'
require_relative '../../apps/api/v2/application'

# Secret Activity capture at creation, v1 and v2 side by side: which
# organization a new receipt is stamped with (org_id), which indexes it joins
# inside the spawn_pair commit, and the 'created' event on the trail.
#
#   creator                         | org_id / trail       | org receipt index
#   --------------------------------+----------------------+------------------
#   member (v1, v2)                 | creator's org        | yes
#   guest on the org's custom domain| domain's org         | no
#   guest on the canonical host     | none                 | no
#
# Later lifecycle events (receipt view, reveal, burn, expiry) load the
# organization from the stamped org_id, so the stamp decides whether a
# secret's whole lifecycle reaches the trail.
RSpec.describe 'Secret Activity capture at creation', type: :integration do
  before(:all) { Onetime.boot! :test }

  let(:run_id) { SecureRandom.hex(6) }
  let(:owner) { Onetime::Customer.create!(email: "capture-#{run_id}@example.com") }
  let(:organization) { Onetime::Organization.create!("Capture #{run_id}", owner, owner.email) }
  let(:domain) { Onetime::CustomDomain.create!("capture-#{run_id}.example.com", organization.objid) }
  # Guests have no customer record (cust is nil since #2733).
  let(:guest) { nil }
  let(:session) { double('Session', anonymous?: false, custid: nil, empty?: true, clear: nil) }

  after do
    domain.destroy! if domain.exists?
    organization.destroy!
    owner.destroy!
  end

  def receipt_ids(collection)
    collection.rangebyscore(0, Familia.now.to_f + 60)
  end

  def trail
    organization.secret_activity_events_page
  end

  # Drives create_secret_pair + handle_success with the state that
  # process_params / validate_sharing_controls would have left behind, so the
  # spec exercises the capture code and not the validation chain.
  def prime(logic, domain_record: nil)
    logic.instance_variable_set(:@kind, :conceal)
    logic.instance_variable_set(:@secret_value, 'capture fixture')
    logic.instance_variable_set(:@ttl, 3600)
    logic.instance_variable_set(:@recipient, [])
    logic.instance_variable_set(:@share_domain, domain_record&.display_domain)
    logic.instance_variable_set(:@selected_sharing_domain, domain_record)
    logic
  end

  def create_v1(cust, org: nil, domain_record: nil)
    logic          = V1::Logic::Secrets::ConcealSecret.new(session, cust, {})
    logic.auth_org = org
    prime(logic, domain_record: domain_record)
    logic.send(:create_secret_pair)
    logic.send(:handle_success)
    logic
  end

  def create_v2(cust, org: nil, domain_record: nil)
    strategy = double('StrategyResult', user: cust, session: {}, auth_method: cust ? 'sessionauth' : 'noauth',
      authenticated?: !cust.nil?, metadata: { organization_context: { organization: org } })
    logic    = V2::Logic::Secrets::ConcealSecret.new(strategy, { 'secret' => {} })
    allow(logic).to receive(:auth_org).and_return(org)
    prime(logic, domain_record: domain_record)
    logic.send(:create_secret_pair)
    logic.send(:handle_success)
    logic
  end

  { 'v1' => :create_v1, 'v2' => :create_v2 }.each do |version, creator|
    describe "#{version} creation" do
      context 'by an organization member' do
        it 'stamps the receipt, indexes it in the commit, and records created once' do
          logic   = send(creator, owner, org: organization, domain_record: domain)
          receipt = Onetime::Receipt.load(logic.receipt.identifier)

          expect(receipt.org_id).to eq(organization.objid)
          expect(receipt.domain_id).to eq(domain.objid)
          expect(receipt_ids(owner.receipts)).to include(receipt.identifier)
          expect(receipt_ids(organization.receipts)).to include(receipt.identifier)
          expect(receipt_ids(domain.receipts)).to include(receipt.identifier)

          created = trail.select { |event| event['kind'] == 'created' }
          expect(created.size).to eq(1)
          expect(created.first).to include('actor' => 'creator', 'actor_id' => owner.objid,
            'receipt' => receipt.shortid)
        end

        it 'sends the later lifecycle events to the same trail' do
          logic = send(creator, owner, org: organization)
          Onetime::Secret.load(logic.secret.identifier).burned!

          expect(trail.map { |event| event['kind'] }).to include('created', 'burned')
        end
      end

      context "by a guest on the organization's custom domain" do
        it "stamps the domain's organization and records an anonymous created event" do
          logic   = send(creator, guest, domain_record: domain)
          receipt = Onetime::Receipt.load(logic.receipt.identifier)

          expect(receipt.org_id).to eq(organization.objid)
          expect(receipt_ids(domain.receipts)).to include(receipt.identifier)

          created = trail.select { |event| event['kind'] == 'created' }
          expect(created.size).to eq(1)
          expect(created.first['actor']).to eq('anonymous')
          expect(created.first).not_to have_key('actor_id')
        end

        it "keeps the guest receipt out of the organization's receipt index" do
          logic = send(creator, guest, domain_record: domain)

          expect(receipt_ids(organization.receipts)).not_to include(logic.receipt.identifier)
        end
      end

      context 'by a guest on the canonical host' do
        it 'stamps no organization and records nothing' do
          logic = send(creator, guest)

          expect(Onetime::Receipt.load(logic.receipt.identifier).org_id.to_s).to be_empty
          expect(trail).to be_empty
        end
      end
    end
  end

  describe 'v1 secret link fetch' do
    let(:receipt_and_secret) do
      logic = create_v1(owner, org: organization)
      [logic.receipt, logic.secret]
    end

    def fetch_v1(cust, secret)
      logic = V1::Logic::Secrets::ShowSecret.new(session, cust, { 'key' => secret.identifier, 'continue' => 'false' })
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    it "records a third party's metadata fetch as secret_get" do
      _receipt, secret = receipt_and_secret
      fetch_v1(guest, secret)

      event = trail.find { |e| e['kind'] == 'secret_get' }
      expect(event).not_to be_nil
      expect(event['actor']).to eq('anonymous')
    end

    it "records the creator's own fetch as previewed" do
      _receipt, secret = receipt_and_secret
      fetch_v1(owner, secret)

      event = trail.find { |e| e['kind'] == 'previewed' }
      expect(event).not_to be_nil
      expect(event).to include('actor' => 'creator', 'actor_id' => owner.objid)
    end
  end
end
