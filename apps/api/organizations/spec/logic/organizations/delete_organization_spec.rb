# apps/api/organizations/spec/logic/organizations/delete_organization_spec.rb
#
# frozen_string_literal: true

# Tests for DeleteOrganization logic (#4196 review follow-up).
#
# The logic performs NO pre-destroy mutations: Organization#destroy! owns the
# member/invitation/instances-registry teardown inside its guarded path, so a
# refusal must leave the org fully intact (members attached, still present in
# Organization.instances). Before destroying, the logic self-heals drifted
# domain memberships (CustomDomain.owners attributes a domain to the org but
# the org.domains sorted set lost it) through the single audited repair op,
# then REFUSES with a request-safe 422 form error: repair-then-refuse, never
# repair-then-delete. The bare-Problem guard in Organization#destroy! stays as
# defense-in-depth (it has no Otto error handler and would surface as a 500).
#
# Real datastore (Valkey on 2163, see spec/config.test.yaml): drift is index
# state, so it is exercised against real keys, mirroring
# spec/unit/onetime/models/organization/destroy_domain_guard_spec.rb. Every
# object and manual index entry created here is registered and removed in
# `after`. It NEVER flushes — the test datastore is shared.
#
# Run: bundle exec rspec apps/api/organizations/spec/logic/organizations/delete_organization_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Organizations::DeleteOrganization, :datastore do
  let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: @owner,
      authenticated?: true,
      metadata: {})
  end

  let(:params) { { 'extid' => @org.extid } }

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    @orgs        = []
    @customers   = []
    @domains     = []
    @owners_keys = [] # manual CustomDomain.owners entries to purge

    @owner  = track_customer(Onetime::Customer.create!(email: "del_org_owner_#{suffix}@onetimesecret.com"))
    @member = track_customer(Onetime::Customer.create!(email: "del_org_member_#{suffix}@onetimesecret.com"))

    @org = track_org(Onetime::Organization.create!("Delete Logic #{suffix}", @owner))
    @org.add_members_instance(@member, through_attrs: { role: 'member' })

    # This spec exercises the delete flow, not authorization or the audit
    # model. Entitlement checks have their own coverage (see
    # update_organization_spec.rb); the repair op's exactly-once audit is
    # pinned in its own spec.
    allow(logic).to receive(:require_entitlement_in!).and_return(true)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)
  end

  after do
    @owners_keys.each do |key|
      Onetime::CustomDomain.owners.remove(key)
    rescue StandardError => ex
      warn "[delete org logic spec] owners cleanup failed: #{ex.class}: #{ex.message}"
    end
    @domains.each do |domain|
      domain.destroy! if domain.exists?
    rescue StandardError => ex
      warn "[delete org logic spec] domain cleanup failed: #{ex.class}: #{ex.message}"
    end
    @orgs.each do |org|
      @customers.each do |cust|
        membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, cust.objid)
        membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
      rescue StandardError => ex
        warn "[delete org logic spec] membership cleanup failed: #{ex.class}: #{ex.message}"
      end
      org.destroy! if org.exists?
    rescue StandardError => ex
      warn "[delete org logic spec] org cleanup failed: #{ex.class}: #{ex.message}"
    end
    @customers.each do |cust|
      cust.destroy! if cust.exists?
    rescue StandardError => ex
      warn "[delete org logic spec] customer cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  def track_customer(cust)
    @customers << cust
    cust
  end

  def track_org(org)
    @orgs << org
    org
  end

  # Build and persist a real CustomDomain record pointing at the org via
  # org_id, WITHOUT adding it to the org's domains sorted set or the owners
  # hashkey — callers opt in to each index to stage the exact state under test.
  def create_domain(display_domain)
    domain = Onetime::CustomDomain.parse(display_domain, @org.objid)
    domain.save
    @domains << domain
    domain
  end

  def put_owners_entry(key, org_id)
    Onetime::CustomDomain.owners.put(key, org_id)
    @owners_keys << key
  end

  def expect_org_intact
    expect(@org.exists?).to be(true)
    expect(Onetime::Organization.in_instances?(@org.objid)).to be(true)
    expect(@org.member?(@owner)).to be(true)
    expect(@org.member?(@member)).to be(true)
  end

  describe 'refusal when domains are attached' do
    it 'raise_concerns refuses with a 422 form error and mutates nothing' do
      domain = create_domain("listed-#{suffix}.example.com")
      domain.add_to_organization_domains(@org, Familia.now.to_f)

      expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
        expect(error.message).to eq('Cannot delete organization with domains. Remove all domains first.')
        expect(error.error_type).to eq(:has_domains)
      end

      expect_org_intact
    end

    it 'process re-checks and refuses when a domain appears after raise_concerns (race)' do
      logic.raise_concerns # no domains yet — passes and loads @organization

      domain = create_domain("raced-#{suffix}.example.com")
      domain.add_to_organization_domains(@org, Familia.now.to_f)

      expect { logic.process }.to raise_error(
        Onetime::FormError, 'Cannot delete organization with domains. Remove all domains first.'
      )

      # The refusal left the org fully intact: no member removal, no
      # instances-registry removal — destroy! was never reached.
      expect_org_intact
      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
    end
  end

  describe 'drifted domain membership (owners says ours, sorted set lost it)' do
    it 'repairs the domain back into org.domains AND refuses the delete' do
      domain = create_domain("drifted-#{suffix}.example.com")
      put_owners_entry(domain.to_s, @org.objid)

      expect(@org.domain_count).to eq(0) # precondition: the set has drifted

      logic.raise_concerns # cheap ZCARD check passes — drift is invisible to it

      expect { logic.process }.to raise_error(
        Onetime::FormError, 'Cannot delete organization with domains. Remove all domains first.'
      )

      # Repair-then-refuse: the domain is back in the sorted set, so the
      # user's domain list now SHOWS it and they can act on it.
      expect(@org.domain?(domain)).to be(true)
      expect_org_intact
    end
  end

  describe 'orphaned domain record (owners says ours, record org_id blank)' do
    # Legacy-data-only shape: CustomDomain#save raises on blank org_id, so a
    # blank org_id can only pre-date that validation. Stage it the same way —
    # save normally, then clear the field with a raw HSET that bypasses #save.
    it 'refuses via the operator path (:needs_org) without assigning ownership' do
      domain = create_domain("orphaned-#{suffix}.example.com")
      domain.hset('org_id', '')
      put_owners_entry(domain.to_s, @org.objid)

      expect(@org.domain_count).to eq(0) # precondition: not in org.domains
      expect(Onetime::CustomDomain.find_by_identifier(domain.to_s).org_id.to_s).to be_empty

      logic.raise_concerns # cheap ZCARD check passes — drift is invisible to it

      # No org: is passed to the repair op, so the orphaned shape returns
      # :needs_org (a refusal, not :repaired) and flows into the
      # unrepairable-drift branch with the operator-facing message.
      expect { logic.process }.to raise_error(Onetime::FormError) do |error|
        expect(error.message).to include("orphaned-#{suffix}.example.com")
        expect(error.message).to include('bin/ots domains doctor')
      end

      # The op mutated NOTHING: orphan repair requires an explicit operator
      # --org decision, never a side effect of a user-initiated delete.
      expect(Onetime::CustomDomain.find_by_identifier(domain.to_s).org_id.to_s).to be_empty
      expect(@org.domain?(domain)).to be(false)
      expect_org_intact
    end
  end

  describe 'repair failure isolation' do
    def stub_repair_to_raise_for(failing_domain)
      allow(Onetime::Operations::Domains::Repair).to receive(:new).and_wrap_original do |original, **kwargs|
        if kwargs[:domain].to_s == failing_domain.to_s
          failing_op = instance_double(Onetime::Operations::Domains::Repair)
          allow(failing_op).to receive(:call).and_raise(RuntimeError, 'repair blew up')
          failing_op
        else
          original.call(**kwargs)
        end
      end
    end

    it 'one failed repair does not abort the others, and the refusal still happens' do
      failing = create_domain("fail-repair-#{suffix}.example.com")
      healthy = create_domain("ok-repair-#{suffix}.example.com")
      put_owners_entry(failing.to_s, @org.objid)
      put_owners_entry(healthy.to_s, @org.objid)

      stub_repair_to_raise_for(failing)

      logic.raise_concerns

      expect { logic.process }.to raise_error(
        Onetime::FormError, 'Cannot delete organization with domains. Remove all domains first.'
      )

      expect(@org.domain?(healthy)).to be(true)  # the other repair still ran
      expect(@org.domain?(failing)).to be(false) # failed repair left it drifted
      expect_org_intact # no partial destroy
    end

    it 'refuses with the operator-facing drift message when every repair fails' do
      failing = create_domain("all-fail-#{suffix}.example.com")
      put_owners_entry(failing.to_s, @org.objid)

      stub_repair_to_raise_for(failing)

      logic.raise_concerns

      expect { logic.process }.to raise_error(Onetime::FormError) do |error|
        expect(error.message).to include("all-fail-#{suffix}.example.com")
        expect(error.message).to include('bin/ots domains doctor')
      end

      expect_org_intact
    end
  end

  describe 'clean organization' do
    it 'destroys the org, removes it from instances, and notifies members' do
      objid = @org.objid

      logic.raise_concerns
      result = logic.process

      expect(result).to include(deleted: true, extid: @org.extid)
      expect(@org.exists?).to be(false)
      expect(Onetime::Organization.in_instances?(objid)).to be(false)

      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :organization_deleted,
        hash_including(email_address: @owner.email, deleted_by: @owner.email),
        fallback: :async_thread,
      )
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :organization_deleted,
        hash_including(email_address: @member.email),
        fallback: :async_thread,
      )
    end
  end
end
