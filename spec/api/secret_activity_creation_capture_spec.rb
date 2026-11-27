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

  # A member's score in an index, or nil when it is not a member. The
  # organization and domain indexes take the receipt object (a bare
  # identifier String serializes differently and never matches); the
  # customer's receipts list stores the identifier string.
  def indexed_at(collection, member)
    collection.score(member)
  end

  def expect_indexed(collection, member)
    expect(indexed_at(collection, member)).to be_within(60).of(Familia.now.to_f)
  end

  def trail
    organization.secret_activity_events_page
  end

  # Drives create_secret_pair + handle_success with the state that
  # process_params / validate_sharing_controls would have left behind, so the
  # spec exercises the capture code and not the validation chain. A guest
  # request through the full Rack stack (domain strategy, controller,
  # validation) is in spec/integration/simple/secret_activity_guest_capture_spec.rb.
  def prime(logic, domain_record: nil, passphrase: nil)
    logic.instance_variable_set(:@kind, :conceal)
    logic.instance_variable_set(:@passphrase, passphrase)
    logic.instance_variable_set(:@secret_value, 'capture fixture')
    logic.instance_variable_set(:@ttl, 3600)
    logic.instance_variable_set(:@recipient, [])
    logic.instance_variable_set(:@share_domain, domain_record&.display_domain)
    logic.instance_variable_set(:@selected_sharing_domain, domain_record)
    logic
  end

  def build_v1(cust, org: nil, domain_record: nil, passphrase: nil)
    logic          = V1::Logic::Secrets::ConcealSecret.new(session, cust, {})
    logic.auth_org = org
    prime(logic, domain_record: domain_record, passphrase: passphrase)
  end

  def build_v2(cust, org: nil, domain_record: nil)
    strategy = double('StrategyResult', user: cust, session: {}, auth_method: cust ? 'sessionauth' : 'noauth',
      authenticated?: !cust.nil?, metadata: { organization_context: { organization: org } })
    logic    = V2::Logic::Secrets::ConcealSecret.new(strategy, { 'secret' => {} })
    allow(logic).to receive(:auth_org).and_return(org)
    prime(logic, domain_record: domain_record)
  end

  def create_v1(...) = commit(build_v1(...))
  def create_v2(...) = commit(build_v2(...))

  def commit(logic)
    logic.send(:create_secret_pair)
    logic.send(:handle_success)
    logic
  end

  { 'v1' => :create_v1, 'v2' => :create_v2 }.each do |version, creator|
    builder = :"build_#{version}"

    describe "#{version} creation" do
      # The organization is resolved once, before the commit. A failing read
      # after the commit must not fail a creation that is already stored.
      it 'records created without resolving the organization again after the commit' do
        logic = send(builder, guest, domain_record: domain)
        logic.send(:create_secret_pair)
        allow(logic).to receive(:receipt_organization).and_raise(Redis::CannotConnectError)
        allow(domain).to receive(:primary_organization).and_raise(Redis::CannotConnectError)

        expect { logic.send(:handle_success) }.not_to raise_error
        expect(trail.count { |event| event['kind'] == 'created' }).to eq(1)
      end

      context 'by an organization member' do
        it 'records created and keeps the link when the customer counter fails' do
          logic = send(builder, owner, org: organization)
          logic.send(:create_secret_pair)
          allow(owner).to receive(:increment_field).with(:secrets_created).and_raise(Redis::CannotConnectError)

          expect { logic.send(:handle_success) }.not_to raise_error
          expect(logic.receipt).not_to be_nil
          expect(trail.count { |event| event['kind'] == 'created' }).to eq(1)
        end

        it 'stamps the receipt, indexes it in the commit, and records created once' do
          logic   = send(creator, owner, org: organization, domain_record: domain)
          receipt = Onetime::Receipt.load(logic.receipt.identifier)

          expect(receipt.org_id).to eq(organization.objid)
          expect(receipt.domain_id).to eq(domain.objid)
          expect_indexed(owner.receipts, receipt.identifier)
          expect_indexed(organization.receipts, receipt)
          expect_indexed(domain.receipts, receipt)

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
          expect_indexed(domain.receipts, receipt)

          created = trail.select { |event| event['kind'] == 'created' }
          expect(created.size).to eq(1)
          expect(created.first['actor']).to eq('anonymous')
          expect(created.first).not_to have_key('actor_id')
        end

        it "keeps the guest receipt out of the organization's receipt index" do
          logic   = send(creator, guest, domain_record: domain)
          receipt = Onetime::Receipt.load(logic.receipt.identifier)

          expect_indexed(domain.receipts, receipt)
          expect(indexed_at(organization.receipts, receipt)).to be_nil
        end

        it "sends the guest secret's later lifecycle events to the same trail" do
          logic = send(creator, guest, domain_record: domain)
          Onetime::Secret.load(logic.secret.identifier).burned!(actor_context: { 'actor' => 'anonymous' })

          burned = trail.find { |event| event['kind'] == 'burned' }
          expect(burned).to include('actor' => 'anonymous')
        end
      end

      context "by a guest on an archived organization's custom domain" do
        it 'stamps no organization and records nothing' do
          domain # created while the organization is live
          organization.archive!
          logic = send(creator, guest, domain_record: domain)

          expect(Onetime::Receipt.load(logic.receipt.identifier).org_id.to_s).to be_empty
          expect(trail).to be_empty
        end
      end

      context 'by a guest on the canonical host' do
        it 'stamps no organization and records nothing' do
          domain # the organization and its domain exist before the creation
          logic = send(creator, guest)

          expect(Onetime::Receipt.load(logic.receipt.identifier).org_id.to_s).to be_empty
          expect(trail).to be_empty
        end
      end
    end
  end

  # The v1 controller (V1::Controllers::Index#show_secret) always sends
  # continue=true, so these fetches go the way a real request does: a fetch
  # either reveals, or fails on the passphrase.
  describe 'v1 secret link fetch' do
    let(:receipt_and_secret) do
      logic = create_v1(owner, org: organization, passphrase: 'right-phrase')
      [logic.receipt, logic.secret]
    end

    def fetch_v1(cust, secret, passphrase:)
      logic = V1::Logic::Secrets::ShowSecret.new(session, cust,
        { 'key' => secret.identifier, 'continue' => 'true', 'passphrase' => passphrase })
      logic.process_params
      logic.raise_concerns
      logic.process
    end

    it "records a third party's wrong-passphrase fetch as secret_get" do
      _receipt, secret = receipt_and_secret
      fetch_v1(guest, secret, passphrase: 'wrong-phrase')

      event = trail.find { |e| e['kind'] == 'secret_get' }
      expect(event).not_to be_nil
      expect(event['actor']).to eq('anonymous')
    end

    it "records a reveal as revealed and not as secret_get" do
      _receipt, secret = receipt_and_secret
      fetch_v1(guest, secret, passphrase: 'right-phrase')

      kinds = trail.map { |e| e['kind'] }
      expect(kinds).to include('revealed')
      expect(kinds).not_to include('secret_get')
    end

    it "records the creator's own wrong-passphrase fetch as previewed" do
      _receipt, secret = receipt_and_secret
      fetch_v1(owner, secret, passphrase: 'wrong-phrase')

      event = trail.find { |e| e['kind'] == 'previewed' }
      expect(event).not_to be_nil
      expect(event).to include('actor' => 'creator', 'actor_id' => owner.objid)
    end
  end
end
