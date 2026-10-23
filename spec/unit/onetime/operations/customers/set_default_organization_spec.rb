# spec/unit/onetime/operations/customers/set_default_organization_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Customers::SetDefaultOrganization, the
# single implementation behind
# `POST /api/colonel/users/:user_id/default-organization` and
# `bin/ots customers set-default-org`.
#
# Real datastore: eligibility is decided by the membership record, the
# organization's member set and its archived flag together, and the result is
# read back through OrganizationLoader, so doubles would not prove the rule.
# The audit sink is stubbed (message expectations; the write paths swallow
# their own errors).
#
# Run: tests/lanes/run unit --only spec/unit/onetime/operations/customers/set_default_organization_spec.rb

require 'spec_helper'
require 'onetime/models/colonel_audit_event'
require 'onetime/operations/customers/set_default_organization'

RSpec.describe Onetime::Operations::Customers::SetDefaultOrganization, :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:actor) { 'ur_colonel_public' }

  before do
    @customers = []
    @orgs      = []

    @owner    = track(@customers, Onetime::Customer.create!(email: "sdo_owner_#{suffix}@onetimesecret.com"))
    @member   = track(@customers, Onetime::Customer.create!(email: "sdo_member_#{suffix}@onetimesecret.com"))
    # The member's own workspace: their effective default before any change.
    @home     = track(@orgs, Onetime::Organization.create!("SDO Home #{suffix}", @member, is_default: true))
    @team     = track(@orgs, Onetime::Organization.create!("SDO Team #{suffix}", @owner))
    @stranger = track(@orgs, Onetime::Organization.create!("SDO Other #{suffix}", @owner))
    @team.add_members_instance(@member, through_attrs: { role: 'member', status: 'active' })

    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::ColonelAuditEvent).to receive(:record_access)
  end

  after do
    @orgs.each { |org| org.destroy! rescue nil } # rubocop:disable Style/RescueModifier
    @customers.each { |cust| cust.destroy! rescue nil } # rubocop:disable Style/RescueModifier
  end

  def track(list, record)
    list << record
    record
  end

  def call_op(organization, customer: @member, **)
    described_class.new(customer: customer, organization: organization, actor: actor, **).call
  end

  def stored_default(customer = @member)
    Onetime::Customer.load(customer.objid).default_org_id.to_s
  end

  describe 'an organization the customer is an active member of' do
    it 'becomes the default and reports the previous one', :aggregate_failures do
      result = call_op(@team)

      expect(result.status).to eq(:success)
      expect(result.organization.extid).to eq(@team.extid)
      expect(result.previous&.extid).to eq(@home.extid)
      expect(stored_default).to eq(@team.objid)

      reloaded = Onetime::Customer.load(@member.objid)
      expect(Onetime::Application::OrganizationLoader.default_organization(reloaded)&.objid).to eq(@team.objid)
    end

    it 'records ONE applied event naming the actor, both organizations and the reason' do
      call_op(@team, reason: 'support ticket 42')

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'customer.set_default_org',
        target: @member.extid,
        result: :success,
        detail: { from: @home.extid, to: @team.extid, org_id: @team.extid, reason: 'support ticket 42' },
      )
    end
  end

  describe 'an organization that is already the default' do
    before { @member.default_org_id!(@team.objid) }

    it 'writes nothing and answers :no_change' do
      result = call_op(@team)

      expect(result.status).to eq(:no_change)
      expect(result.previous&.extid).to eq(@team.extid)
      expect(stored_default).to eq(@team.objid)
    end

    it 'still records the attempt, marked no_change (#4337)' do
      call_op(@team)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        actor: actor,
        verb: 'customer.set_default_org',
        target: @member.extid,
        result: :success,
        detail: { from: @team.extid, to: @team.extid, org_id: @team.extid, outcome: 'no_change' },
      )
    end
  end

  describe 'refusals' do
    shared_examples 'a refused default change' do |status|
      it "answers #{status}, writes nothing and records ONE failure event", :aggregate_failures do
        result = call_op(target_org)

        expect(result.status).to eq(status)
        expect(result).to be_refused
        expect(stored_default).to eq('')
        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'customer.set_default_org',
          target: @member.extid,
          result: :failure,
          detail: { reason: status.to_s, org_id: target_org.extid },
        )
      end
    end

    context 'when the customer is not a member' do
      let(:target_org) { @stranger }

      include_examples 'a refused default change', :not_member
    end

    # A pending invitation is not membership.
    context 'when the customer only holds a pending invitation' do
      let(:target_org) { @stranger }

      before do
        Onetime::OrganizationMembership.create_invitation!(
          organization: @stranger, email: @member.email, inviter: @owner, role: 'member',
        )
      end

      include_examples 'a refused default change', :not_member
    end

    context 'when the organization is archived' do
      let(:target_org) { @team }

      before { @team.archive! }

      include_examples 'a refused default change', :archived
    end

    it 'refuses an anonymous customer without reading memberships' do
      anon = instance_double(Onetime::Customer, anonymous?: true, extid: 'anon', objid: 'anon')
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)

      result = call_op(@team, customer: anon)

      expect(result.status).to eq(:anonymous)
      expect(Onetime::OrganizationMembership).not_to have_received(:find_by_org_customer)
    end
  end

  describe 'dry run' do
    it 'checks eligibility, writes nothing, and records a preview observation only', :aggregate_failures do
      result = call_op(@team, dry_run: true)

      expect(result.status).to eq(:dry_run)
      expect(result.dry_run).to be true
      expect(result.previous&.extid).to eq(@home.extid)
      expect(stored_default).to eq('')
      expect(Onetime::ColonelAuditEvent).to have_received(:record_access).once.with(
        actor: actor,
        verb: 'customer.set_default_org',
        target: @member.extid,
        result: 'preview',
        detail: { from: @home.extid, to: @team.extid, org_id: @team.extid, dry_run: true },
      )
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'still refuses a non-member, marking the refusal as a dry run' do
      result = call_op(@stranger, dry_run: true)

      expect(result.status).to eq(:not_member)
      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(result: :failure, detail: { reason: 'not_member', org_id: @stranger.extid, dry_run: true }),
      )
    end
  end

  # Onetime::AuditedFailure: the success record sits after the write, so a
  # raise there would otherwise leave no trace.
  it 'records ONE failure event when the write raises, and re-raises' do
    allow(@member).to receive(:default_org_id!).and_raise(Redis::CannotConnectError, 'down')

    expect { call_op(@team) }.to raise_error(Redis::CannotConnectError)
    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(actor: actor, verb: 'customer.set_default_org', target: @member.extid, result: :failure),
    )
  end
end
