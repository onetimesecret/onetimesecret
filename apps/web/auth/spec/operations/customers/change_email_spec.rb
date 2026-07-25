# apps/web/auth/spec/operations/customers/change_email_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::ChangeEmail.
#
# This is a cross-store mutation (Postgres accounts row + Redis Customer and
# three indexes) with no distributed transaction, so the contract these examples
# pin down is mostly about ORDER and FAILURE:
#
#   * SQL is written BEFORE any Redis write (a SQL failure must leave Redis clean)
#   * the class email index is re-keyed with the OLD address, before save
#   * a Redis failure after the SQL commit yields :partial — never a raise past a
#     committed mutation, because that would lose the audit
#   * the compensating SQL write-back fires ONLY when the Customer hash never
#     committed the new address (otherwise it would manufacture drift)
#   * exactly one `customer.change_email` audit event, with OBSCURED addresses
#
# Every collaborator is stubbed: no datastore, no auth DB, no mail.
#
# Run: bundle exec rspec apps/web/auth/spec/operations/customers/change_email_spec.rb

require 'spec_helper'
require 'onetime/models/admin_audit_event'
require 'auth/database'
require 'auth/operations/customers/change_email'

RSpec.describe Auth::Operations::Customers::ChangeEmail do
  # Ordered trace of the cross-store writes, so ordering is asserted on facts
  # rather than on RSpec's `.ordered` bookkeeping.
  let(:trace) { [] }

  let(:old_email) { 'old@example.com' }
  let(:new_email) { 'new@example.com' }

  let(:pending_change) { double('pending_email_change', to_s: '', delete!: true) }
  let(:pending_status) { double('pending_email_delivery_status', delete!: true) }

  let(:customer) do
    cust = double(
      'Customer',
      extid: 'ur_c',
      objid: 'obj_c',
      anonymous?: false,
      locale: 'en',
      obscure_email: 'ol***@e***.com',
      organization_instances: [],
      pending_email_change: pending_change,
      pending_email_delivery_status: pending_status,
    )
    allow(cust).to receive(:email).and_return(old_email)
    allow(cust).to receive(:email=) { |value| trace << [:customer_email_assigned, value] }
    allow(cust).to receive(:update_in_class_email_index) { |old| trace << [:class_index_rekey, old] }
    allow(cust).to receive(:update_in_organization_email_index) { |org, old| trace << [:org_index_rekey, org, old] }
    allow(cust).to receive(:save) { trace << [:customer_save] }
    cust
  end

  # --- Redis index doubles -------------------------------------------------
  let(:email_index)         { double('Customer.email_index', get: nil) }
  let(:contact_email_index) { double('Organization.contact_email_index', get: nil) }

  # --- SQL doubles ---------------------------------------------------------
  # db[:accounts].where(...)  is called with three different filters; each gets
  # its own leaf double so the examples can drive them independently.
  let(:my_account_row)  { { id: 42, email: old_email } }
  let(:collision_rows)  { [] }

  let(:by_external_id) { double('by_external_id') }
  let(:by_email)       { double('by_email') }
  let(:by_id)          { double('by_id') }
  let(:accounts)       { double('accounts') }
  let(:db)             { double('db') }

  # --- delegated ops -------------------------------------------------------
  let(:revoker)  { instance_double(Onetime::Operations::Sessions::RevokeAllForCustomer, call: nil) }
  let(:verifier) { instance_double(Auth::Operations::Customers::SetVerification, call: :success) }

  before do
    allow(Onetime::AdminAuditEvent).to receive(:record)
    allow(OT).to receive(:info)
    allow(Onetime::Customer).to receive(:email_index).and_return(email_index)
    allow(Onetime::Organization).to receive(:contact_email_index).and_return(contact_email_index)
    allow(Onetime::EmailSuppression).to receive(:suppressed?).and_return(false)
    allow(Onetime::OrganizationMembership).to receive(:find_pending_by_email).and_return(nil)
    allow(Onetime::Secret).to receive(:find_by_identifier).and_return(nil)
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)

    allow(Onetime::Operations::Sessions::RevokeAllForCustomer).to receive(:new).and_return(revoker)
    allow(Auth::Operations::Customers::SetVerification).to receive(:new).and_return(verifier)

    # SQL wiring
    allow(db).to receive(:[]).with(:accounts).and_return(accounts)
    allow(db).to receive(:transaction) { |&blk| blk.call }
    allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
    allow(accounts).to receive(:where).with(email: new_email).and_return(by_email)
    allow(accounts).to receive(:where).with(id: 42).and_return(by_id)
    allow(by_external_id).to receive(:select).with(:id, :email).and_return(by_external_id)
    allow(by_external_id).to receive(:first).and_return(my_account_row)
    allow(by_email).to receive(:select).with(:id, :status_id).and_return(by_email)
    allow(by_email).to receive(:all) { collision_rows }
    allow(by_id).to receive(:update) do |attrs|
      trace << [:sql_update, attrs[:email]]
      1
    end
  end

  def op(**overrides)
    described_class.new(
      **{
        customer: customer,
        new_email: new_email,
        actor: 'cli',
        dry_run: false,
        db: db,
      }.merge(overrides)
    )
  end

  # =========================================================================
  describe 'happy path' do
    it 'returns :success with every Result field populated' do
      result = op.call

      expect(result.status).to eq(:success)
      expect(result.extid).to eq('ur_c')
      expect(result.from).to eq(old_email)
      expect(result.to).to eq(new_email)
      expect(result.dry_run).to be false
      expect(result.auth_row_updated).to be true
      expect(result.orgs_reindexed).to eq(0)
      expect(result.sessions_revoked).to be true
      expect(result.verification_reset).to be true
      expect(result.warnings).to eq([])
    end

    it 'writes SQL BEFORE Redis, and re-keys the class index with the OLD address before save' do
      op.call

      expect(trace).to eq(
        [
          [:sql_update, new_email],
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:customer_save],
        ]
      )
    end

    it 'records exactly one audit event with OBSCURED addresses' do
      op.call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once
      expect(Onetime::AdminAuditEvent).to have_received(:record).with(
        actor: 'cli',
        verb: 'customer.change_email',
        target: 'ur_c',
        result: :success,
        detail: hash_including(
          from: OT::Utils.obscure_email(old_email),
          to: OT::Utils.obscure_email(new_email),
          auth_row_updated: true,
          orgs_reindexed: 0,
          require_verification: true,
        ),
      )
    end

    it 'never puts a raw address in the audit detail' do
      op.call

      detail = nil
      expect(Onetime::AdminAuditEvent).to have_received(:record) { |kwargs| detail = kwargs[:detail] }
      expect(detail[:from]).not_to eq(old_email)
      expect(detail[:to]).not_to eq(new_email)
    end

    it 'normalizes the new address once, for the collision check AND the stored value' do
      expect(email_index).to receive(:get).with(new_email).and_return(nil)

      result = op(new_email: '  NEW@Example.COM ').call

      expect(result.to).to eq(new_email)
      expect(trace).to include([:customer_email_assigned, new_email])
    end
  end

  # =========================================================================
  describe 'dry run (the default)' do
    it 'defaults to dry_run: true' do
      result = described_class.new(customer: customer, new_email: new_email, actor: 'cli', db: db).call

      expect(result.status).to eq(:planned)
      expect(result.dry_run).to be true
    end

    it 'mutates nothing and audits nothing' do
      op(dry_run: true).call

      expect(trace).to be_empty
      expect(customer).not_to have_received(:save)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'reports how many orgs WOULD be re-indexed' do
      allow(customer).to receive(:organization_instances).and_return([double('org'), double('org')])

      expect(op(dry_run: true).call.orgs_reindexed).to eq(2)
    end
  end

  # =========================================================================
  describe 'guards' do
    it 'returns :not_found for a nil customer' do
      expect(op(customer: nil).call.status).to eq(:not_found)
    end

    it 'returns :not_found for an anonymous customer' do
      allow(customer).to receive(:anonymous?).and_return(true)

      expect(op.call.status).to eq(:not_found)
      expect(customer).not_to have_received(:save)
    end

    it 'returns :invalid_email for a malformed address' do
      result = op(new_email: 'not-an-email').call

      expect(result.status).to eq(:invalid_email)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    it 'returns :no_change when the normalized address matches the current one' do
      result = op(new_email: '  OLD@Example.com ').call

      expect(result.status).to eq(:no_change)
      expect(customer).not_to have_received(:save)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  # =========================================================================
  describe 'collision detection (three distinct sources)' do
    it 'source 1: the Redis email index already points the address at someone else' do
      allow(email_index).to receive(:get).with(new_email).and_return('obj_other')

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(trace).to be_empty
    end

    it 'ignores a Redis index entry that points at the target customer itself (drift, not a collision)' do
      allow(email_index).to receive(:get).with(new_email).and_return('obj_c')

      expect(op.call.status).to eq(:success)
    end

    it 'source 2: a LIVE accounts row already holds the address' do
      collision_rows.replace([{ id: 99, status_id: 2 }])

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(trace).to be_empty
    end

    it "ignores the target's own accounts row in the SQL probe" do
      collision_rows.replace([{ id: 42, status_id: 2 }])

      expect(op.call.status).to eq(:success)
    end

    it 'source 3: the unique constraint fires on the UPDATE (TOCTOU close-out)' do
      allow(by_id).to receive(:update).and_raise(Sequel::UniqueConstraintViolation, 'dup')

      result = op.call

      expect(result.status).to eq(:email_taken)
      expect(customer).not_to have_received(:save)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end

    # A CLOSED account (status_id 3) sits outside the partial unique index AND
    # outside Customer.email_exists?, so it is invisible to both normal checks.
    it 'treats an address held by a CLOSED account as taken by default' do
      collision_rows.replace([{ id: 99, status_id: 3 }])

      expect(op.call.status).to eq(:email_taken)
    end

    it 'allows closed-account reuse when explicitly requested, with a warning' do
      collision_rows.replace([{ id: 99, status_id: 3 }])

      result = op(allow_closed_account_reuse: true).call

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:new_address_held_by_closed_account)
    end

    it 'warns rather than silently passing when the SQL probe itself fails' do
      allow(by_email).to receive(:all).and_raise(StandardError, 'db down')

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:sql_collision_probe_failed)
    end
  end

  # =========================================================================
  describe 'SQL failure leaves Redis untouched' do
    it 're-raises a non-uniqueness SQL error without touching the Customer' do
      allow(by_id).to receive(:update).and_raise(StandardError, 'connection reset')

      expect { op.call }.to raise_error(StandardError, 'connection reset')
      expect(customer).not_to have_received(:save)
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end

  # =========================================================================
  describe ':partial — Redis fails after the SQL commit' do
    it 'compensates the SQL row back to the old address when the Customer never committed' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      result = op.call

      expect(result.status).to eq(:partial)
      expect(result.warnings).to include(:auth_row_rolled_back)
      expect(trace).to eq(
        [
          [:sql_update, new_email],
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:sql_update, old_email], # the compensating write-back
        ]
      )
    end

    it 'still records exactly one audit event, with result: :partial' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      op.call

      expect(Onetime::AdminAuditEvent).to have_received(:record).once.with(
        hash_including(verb: 'customer.change_email', result: :partial)
      )
    end

    it 'reports auth_row_updated: false once the row has been rolled back' do
      allow(customer).to receive(:save).and_raise(StandardError, 'redis down')

      expect(op.call.auth_row_updated).to be false
    end

    # Rolling SQL back here would MANUFACTURE the drift the compensation exists
    # to prevent: both authoritative stores already hold the new address.
    # Driven through the pending-marker teardown, which is deliberately NOT
    # rescued (a surviving marker means a live token can revert the change).
    it 'does NOT roll SQL back when the Customer hash already committed' do
      allow(customer).to receive(:pending_email_change).and_raise(StandardError, 'redis blip')

      result = op.call

      expect(result.status).to eq(:partial)
      expect(result.warnings).to include(:secondary_writes_incomplete)
      expect(result.auth_row_updated).to be true
      expect(trace.count { |entry| entry.first == :sql_update }).to eq(1)
    end
  end

  # =========================================================================
  describe 'organization indexes' do
    let(:org_a) { double('org_a', extid: 'og_a', identifier: 'og_a', is_default: 'false', contact_email: '') }
    let(:org_b) { double('org_b', extid: 'og_b', identifier: 'og_b', is_default: 'false', contact_email: '') }

    before { allow(customer).to receive(:organization_instances).and_return([org_a, org_b]) }

    it 're-keys the org-scoped index once per org, with the OLD address' do
      result = op.call

      expect(result.orgs_reindexed).to eq(2)
      expect(trace).to include([:org_index_rekey, org_a, old_email], [:org_index_rekey, org_b, old_email])
    end

    it 'warns and keeps going when one org fails' do
      allow(customer).to receive(:update_in_organization_email_index) do |org, old|
        raise StandardError, 'boom' if org == org_a

        trace << [:org_index_rekey, org, old]
      end

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.orgs_reindexed).to eq(1)
      expect(result.warnings).to include(:org_email_index_failed)
    end
  end

  # =========================================================================
  describe 'organization contact_email (D39)' do
    let(:default_org) do
      org = double('default_org', extid: 'og_d', identifier: 'og_d', is_default: 'true', contact_email: old_email)
      # Stubbed so the negative assertions below are real spy assertions, not
      # "that object is not a spy" errors.
      allow(org).to receive(:billing_email=)
      allow(org).to receive(:stripe_checkout_email=)
      allow(org).to receive(:email_hash=)
      allow(org).to receive(:contact_email=) { |value| trace << [:org_contact_assigned, value] }
      allow(org).to receive(:update_in_class_contact_email_index) { |old| trace << [:org_contact_rekey, old] }
      allow(org).to receive(:save) { trace << [:org_save] }
      org
    end

    let(:shared_org) do
      org = double('shared_org', extid: 'og_s', identifier: 'og_s', is_default: 'false', contact_email: old_email)
      allow(org).to receive(:contact_email=)
      allow(org).to receive(:save)
      org
    end

    it 'rewrites the contact of a default org whose contact_email is the OLD address' do
      allow(customer).to receive(:organization_instances).and_return([default_org])

      result = op.call

      expect(result.warnings).to include(:org_contact_email_updated)
      expect(trace).to include([:org_contact_assigned, new_email], [:org_contact_rekey, old_email], [:org_save])
    end

    it 'NEVER rewrites a shared (non-default) org contact' do
      allow(customer).to receive(:organization_instances).and_return([shared_org])

      result = op.call

      expect(result.warnings).not_to include(:org_contact_email_updated)
      expect(shared_org).not_to have_received(:contact_email=)
      expect(shared_org).not_to have_received(:save)
    end

    it 'skips (and warns) when another org already holds the new address as its contact' do
      allow(customer).to receive(:organization_instances).and_return([default_org])
      allow(contact_email_index).to receive(:get).with(new_email).and_return('og_other')

      result = op.call

      expect(result.warnings).to include(:org_contact_email_conflict)
      expect(default_org).not_to have_received(:contact_email=)
    end

    it 'never touches billing_email / stripe_checkout_email / email_hash' do
      allow(customer).to receive(:organization_instances).and_return([default_org])

      op.call

      %i[billing_email= stripe_checkout_email= email_hash=].each do |setter|
        expect(default_org).not_to have_received(setter)
      end
    end
  end

  # =========================================================================
  describe 'pending self-service email change' do
    it 'clears both pending markers' do
      op.call

      expect(pending_change).to have_received(:delete!)
      expect(pending_status).to have_received(:delete!)
    end

    it 'destroys a live pending verification secret and warns' do
      secret = double('Secret', destroy!: true)
      allow(customer).to receive(:pending_email_change).and_return(
        double('pending', to_s: 'tok_live', delete!: true)
      )
      allow(Onetime::Secret).to receive(:find_by_identifier).with('tok_live').and_return(secret)

      result = op.call

      expect(secret).to have_received(:destroy!)
      expect(result.warnings).to include(:pending_self_service_change_cleared)
    end
  end

  # =========================================================================
  describe 'delegation to sibling ops (one audit event per VERB)' do
    it 'delegates session revocation to RevokeAllForCustomer' do
      op.call

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).to have_received(:new).with(
        custid: 'ur_c', actor: 'cli'
      )
    end

    it 'skips session revocation when revoke_sessions is false' do
      result = op(revoke_sessions: false).call

      expect(Onetime::Operations::Sessions::RevokeAllForCustomer).not_to have_received(:new)
      expect(result.sessions_revoked).to be false
    end

    it 'resets verification through SetVerification when require_verification is true' do
      op.call

      expect(Auth::Operations::Customers::SetVerification).to have_received(:new).with(
        customer: customer, verified: false, actor: 'cli', verified_by: nil, db: db
      )
    end

    it 'leaves verification alone when require_verification is false (the token path)' do
      result = op(require_verification: false).call

      expect(Auth::Operations::Customers::SetVerification).not_to have_received(:new)
      expect(result.verification_reset).to be false
    end

    it 'warns instead of raising when the verification reset fails after the swap' do
      allow(verifier).to receive(:call).and_raise(StandardError, 'no auth db')

      result = op.call

      expect(result.status).to eq(:success)
      expect(result.warnings).to include(:verification_reset_failed)
    end
  end

  # =========================================================================
  describe 'notifications (D36)' do
    it 'mails BOTH the old and the new address' do
      op.call

      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).twice
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :email_changed, hash_including(recipient: old_email), hash_including(fallback: :async_thread)
      )
      expect(Onetime::Jobs::Publisher).to have_received(:enqueue_email).with(
        :email_changed, hash_including(recipient: new_email), hash_including(fallback: :async_thread)
      )
    end

    it 'sends nothing when notify is false (compromised-account remediation)' do
      op(notify: false).call

      expect(Onetime::Jobs::Publisher).not_to have_received(:enqueue_email)
    end
  end

  # =========================================================================
  describe 'report-only warnings' do
    it 'warns when the NEW address is already suppressed' do
      allow(Onetime::EmailSuppression).to receive(:suppressed?).with(new_email).and_return(true)

      expect(op.call.warnings).to include(:new_address_suppressed)
    end

    it 'warns about pending invitations addressed to the OLD address, and never rewrites them' do
      org        = double('org', extid: 'og_i', identifier: 'og_i', is_default: 'false', contact_email: '')
      invitation = double('OrganizationMembership', :invited_email= => nil)
      allow(customer).to receive(:organization_instances).and_return([org])
      allow(Onetime::OrganizationMembership).to receive(:find_pending_by_email)
        .with(org, old_email).and_return(invitation)

      result = op.call

      expect(result.warnings).to include(:pending_invitations_orphaned)
      expect(invitation).not_to have_received(:invited_email=)
    end
  end

  # =========================================================================
  describe 'audit provenance (D41)' do
    it 'records --reason and --ticket in the audit detail when supplied' do
      op(reason: 'support request', ticket: 'ZD-9182').call

      expect(Onetime::AdminAuditEvent).to have_received(:record).with(
        hash_including(detail: hash_including(reason: 'support request', ticket: 'ZD-9182'))
      )
    end

    it 'omits them entirely when blank' do
      op(reason: '  ', ticket: nil).call

      detail = nil
      expect(Onetime::AdminAuditEvent).to have_received(:record) { |kwargs| detail = kwargs[:detail] }
      expect(detail).not_to have_key(:reason)
      expect(detail).not_to have_key(:ticket)
    end
  end

  # =========================================================================
  describe 'simple mode (no auth database)' do
    before { allow(Auth::Database).to receive(:connection).and_return(nil) }

    it 'degrades to Redis-only and reports auth_row_updated: false, never a phantom success' do
      result = op(db: nil).call

      expect(result.status).to eq(:success)
      expect(result.auth_row_updated).to be false
      expect(trace).to eq(
        [
          [:customer_email_assigned, new_email],
          [:class_index_rekey, old_email],
          [:customer_save],
        ]
      )
    end

    # The last-moment re-read narrows the window; it is NOT a CAS and cannot
    # close it (Familia's update_in_class_email_index is a blind MULTI).
    it 'aborts with :email_taken when the late re-read finds the address claimed' do
      allow(email_index).to receive(:get).with(new_email).and_return(nil, 'obj_other')

      result = op(db: nil).call

      expect(result.status).to eq(:email_taken)
      expect(customer).not_to have_received(:save)
    end
  end
end
