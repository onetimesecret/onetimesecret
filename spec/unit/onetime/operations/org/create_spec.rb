# spec/unit/onetime/operations/org/create_spec.rb
#
# frozen_string_literal: true

# Unit tests for Onetime::Operations::Org::Create (#3731).
#
# TWO LAYERS, on purpose:
#
#   1. Mocked contract (no datastore) — normalization, the validation ruleset,
#      the exactly-once audit event, the negative "a rejection writes and audits
#      NOTHING" assertions, and the TOCTOU rescue around the contact_email
#      reservation. Organization.create! is stubbed at the class boundary; it
#      has its own coverage.
#
#   2. Real datastore (Valkey on 2121, see spec/config.test.yaml) — the
#      post-condition that actually matters: an org this op created passes ALL
#      FIVE `bin/ots org doctor` invariants. That is unprovable with mocks
#      because the owner membership is a Familia through-model created during
#      the write. The five checks live in
#      spec/support/helpers/org_doctor_invariants.rb (`org_doctor_issues`),
#      shared with the transfer-ownership op's spec.
#
# Layer 2 registers every object it creates and destroys them in `after`. It
# NEVER flushes — the test datastore is shared.
#
# Run: bundle exec rspec spec/unit/onetime/operations/org/create_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'onetime/operations/org/create'

RSpec.describe Onetime::Operations::Org::Create do
  let(:actor) { 'ur_col_public_extid' } # PUBLIC identity (extid/email)

  describe 'mocked contract' do
    let(:owner) do
      instance_double(
        Onetime::Customer,
        anonymous?: false,
        extid: 'ur_owner_ext',
        objid: 'cust-obj-1',
        custid: 'cust-obj-1',
      )
    end

    let(:org) do
      instance_double(
        Onetime::Organization,
        extid: 'on_new_ext',
        objid: 'org-obj-1',
        display_name: 'Acme',
        owner_id: 'cust-obj-1',
        save: true,
      )
    end

    before do
      allow(Onetime::AdminAuditEvent).to receive(:record)
      allow(Onetime::Organization).to receive(:create!).and_return(org)
      allow(Onetime::Organization).to receive(:contact_email_exists?).and_return(false)
      allow(org).to receive(:description=)
      allow(org).to receive(:owner_id=)
    end

    def build(**overrides)
      described_class.new(
        **{ display_name: 'Acme', owner: owner, actor: actor }.merge(overrides)
      )
    end

    describe 'happy path' do
      it 'creates through Organization.create! and returns a populated Result' do
        result = build(contact_email: 'Billing@Acme.test').call

        expect(result.status).to eq(:created)
        expect(result.org_id).to eq('on_new_ext')
        expect(result.objid).to eq('org-obj-1')
        expect(result.display_name).to eq('Acme')
        expect(result.owner_id).to eq('ur_owner_ext') # PUBLIC extid, not the objid
        expect(result.contact_email).to eq('billing@acme.test')
        expect(result.message).to be_nil
        expect(Onetime::Organization)
          .to have_received(:create!).with('Acme', owner, 'billing@acme.test').once
      end

      it 'records EXACTLY ONE audit event, public ids only' do
        build.call

        expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
          actor: actor,
          verb: 'organization.create',
          target: 'on_new_ext',
          result: :success,
          detail: { display_name: 'Acme', owner_id: 'ur_owner_ext' },
        )
      end

      it 'uses the full-noun audit verb the rest of the trail uses' do
        expect(described_class::AUDIT_VERB).to eq('organization.create')
      end

      it 'strips the display name and drops a blank contact_email without an index read' do
        result = build(display_name: '  Acme  ', contact_email: '   ').call

        expect(result.contact_email).to be_nil
        expect(Onetime::Organization).to have_received(:create!).with('Acme', owner, nil)
        expect(Onetime::Organization).not_to have_received(:contact_email_exists?)
      end
    end

    describe 'description' do
      it 'writes and saves the description when present' do
        build(description: '  Primary tenant  ').call

        expect(org).to have_received(:description=).with('Primary tenant')
        expect(org).to have_received(:save).once
      end

      it 'does not touch the org again when absent' do
        build.call

        expect(org).not_to have_received(:description=)
        expect(org).not_to have_received(:save)
      end
    end

    describe 'owner_id normalization (D31)' do
      it 'leaves owner_id alone when create! already wrote the objid' do
        build.call

        expect(org).not_to have_received(:owner_id=)
        expect(org).not_to have_received(:save)
      end

      it 'rewrites owner_id to the OBJID when create! wrote a different custid' do
        allow(org).to receive(:owner_id).and_return('legacy-custid')

        build.call

        expect(org).to have_received(:owner_id=).with('cust-obj-1')
        expect(org).to have_received(:save).once
      end
    end

    describe 'rejections' do
      {
        missing_owner: { owner: nil },
        anonymous_owner: {},
        blank_name: { display_name: '   ' },
        name_too_long: { display_name: 'a' * 101 },
        description_too_long: { description: 'd' * 501 },
        email_taken: { contact_email: 'taken@acme.test' },
      }.each do |status, overrides|
        it "returns :#{status} and mutates + audits NOTHING" do
          allow(owner).to receive(:anonymous?).and_return(true) if status == :anonymous_owner
          allow(Onetime::Organization).to receive(:contact_email_exists?).and_return(true) if status == :email_taken

          result = build(**overrides).call

          expect(result.status).to eq(status)
          expect(result.message).to eq(described_class::REJECTIONS.fetch(status))
          expect(result.org_id).to be_nil
          expect(result.objid).to be_nil
          expect(Onetime::Organization).not_to have_received(:create!)
          expect(Onetime::AdminAuditEvent).not_to have_received(:record)
        end
      end

      it 'accepts a name at exactly MAX_DISPLAY_NAME and a description at exactly MAX_DESCRIPTION' do
        result = build(
          display_name: 'a' * described_class::MAX_DISPLAY_NAME,
          description: 'd' * described_class::MAX_DESCRIPTION,
        ).call

        expect(result.status).to eq(:created)
      end

      it 'pins the limits to the incumbent customer-facing values' do
        expect(described_class::MAX_DISPLAY_NAME).to eq(100)
        expect(described_class::MAX_DESCRIPTION).to eq(500)
      end
    end

    describe 'contact_email race (the real uniqueness guard)' do
      it 'maps the create! reservation failure to :email_taken without raising' do
        allow(Onetime::Organization).to receive(:create!)
          .and_raise(Onetime::Problem.new('Organization exists for that email address'))

        result = nil
        expect { result = build(contact_email: 'billing@acme.test').call }.not_to raise_error

        expect(result.status).to eq(:email_taken)
        expect(result.message).to eq('Organization exists for that email address')
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      it 're-raises any other Onetime::Problem instead of laundering it into a rejection' do
        allow(Onetime::Organization).to receive(:create!)
          .and_raise(Onetime::Problem.new('Display name required'))

        expect { build.call }.to raise_error(Onetime::Problem, 'Display name required')
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end
    end

    describe '#validate' do
      it 'is pure — repeated calls write nothing and audit nothing' do
        op = build(contact_email: 'billing@acme.test')

        2.times { expect(op.validate.status).to eq(:ok) }

        expect(Onetime::Organization).not_to have_received(:create!)
        expect(Onetime::AdminAuditEvent).not_to have_received(:record)
      end

      it 'returns the normalized values an HTTP adapter would echo back' do
        check = build(display_name: ' Acme ', description: ' Tenant ', contact_email: ' Billing@ACME.test ').validate

        expect(check.status).to eq(:ok)
        expect(check.display_name).to eq('Acme')
        expect(check.description).to eq('Tenant')
        expect(check.contact_email).to eq('billing@acme.test')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Layer 2 — real datastore. Proves the post-condition the mocked layer cannot.
  # ---------------------------------------------------------------------------
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    let(:owner_email) { "org_create_owner_#{suffix}@onetimesecret.com" }

    before do
      # Layer 2 exercises the WRITE path, not the audit model.
      allow(Onetime::AdminAuditEvent).to receive(:record)
      @orgs            = []
      @customers       = []
      @reserved_emails = []
      @owner           = track_customer(Onetime::Customer.create!(email: owner_email))
    end

    after do
      @orgs.each do |org|
        membership = Onetime::OrganizationMembership.find_by_org_customer(org.objid, @owner.objid)
        membership.destroy! if membership.respond_to?(:exists?) && membership.exists?
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[org create spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @reserved_emails.each do |email|
        Onetime::Organization.contact_email_index.remove(email)
      rescue StandardError => ex
        warn "[org create spec] index cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[org create spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def track_customer(cust)
      @customers << cust
      cust
    end

    def create_org(**overrides)
      params = {
        display_name: "Acme #{suffix}",
        owner: @owner,
        actor: actor,
      }.merge(overrides)
      @reserved_emails << params[:contact_email] if params[:contact_email]

      result = described_class.new(**params).call
      if result.status == :created
        org = Onetime::Organization.load(result.objid)
        @orgs << org if org
      end
      result
    end

    it 'produces an org that passes ALL FIVE bin/ots org doctor checks' do
      result = create_org(contact_email: "billing_#{suffix}@onetimesecret.com")
      expect(result.status).to eq(:created)

      org = Onetime::Organization.load(result.objid)
      expect(org).not_to be_nil
      expect(org_doctor_issues(org)).to be_empty
    end

    it 'writes owner_id as the OBJID (what doctor check 1 loads by)' do
      org = Onetime::Organization.load(create_org.objid)

      expect(org.owner_id).to eq(@owner.objid)
      expect(Onetime::Customer.load(org.owner_id)).not_to be_nil
    end

    # #3907: create! itself writes the objid, so the signup path
    # (CreateOrganization), which calls create! WITHOUT this op's D31
    # normalization, also lands orgs that satisfy doctor checks 1, 2 and 4.
    # Provable only by bypassing the op — through it, normalize_owner_id!
    # would mask a create! regression.
    it 'needs no D31 normalization: bare Organization.create! writes the objid' do
      org = Onetime::Organization.create!("Bare #{suffix}", @owner)
      @orgs << org

      expect(org.owner_id).to eq(@owner.objid)
      expect(org_doctor_issues(org)).to be_empty
    end

    it 'lands exactly one active owner membership' do
      org        = Onetime::Organization.load(create_org.objid)
      membership = org_owner_membership(org, @owner)

      expect(membership).not_to be_nil
      expect(membership.active?).to be(true)
      expect(membership.role).to eq('owner')
      # What Memberships::Support#sole_owner? reads — only provable for real,
      # because the through-model persists during add_members_instance.
      expect(Onetime::OrganizationMembership.active_for_org(org).count(&:owner?)).to eq(1)
      expect(org.member_count).to eq(1)
    end

    it 'persists the description' do
      org = Onetime::Organization.load(create_org(description: 'Primary tenant').objid)

      expect(org.description).to eq('Primary tenant')
    end

    it 'refuses a duplicate contact_email and leaves exactly one org in the index' do
      email = "billing_dup_#{suffix}@onetimesecret.com"
      first = create_org(contact_email: email)
      expect(first.status).to eq(:created)

      second = create_org(display_name: "Acme Two #{suffix}", contact_email: email)

      expect(second.status).to eq(:email_taken)
      expect(second.org_id).to be_nil
      expect(Onetime::Organization.find_by_contact_email(email).objid).to eq(first.objid)
    end
  end
end
