# apps/web/auth/spec/operations/customers/doctor_email_drift_spec.rb
#
# frozen_string_literal: true

# Unit tests for the three email-drift checks added to
# Auth::Operations::Customers::Doctor by #3731 PR-C1:
#
#   :auth_email_drift       — the ONLY Redis-vs-SQL comparison in the doctor.
#                             Without it a ChangeEmail run that returned
#                             :partial is undetectable, because every other
#                             check compares Redis against Redis.
#   :org_email_index_stale  — the org-scoped index Familia never auto-populates.
#   :org_contact_email_stale — default workspaces contacting a dead address.
#
# The checks are private and are exercised directly rather than through #call,
# so that a failure here names the check that broke instead of dragging in the
# seven unrelated per-customer checks (and the customer double they'd need).
#
# Run: bundle exec rspec apps/web/auth/spec/operations/customers/doctor_email_drift_spec.rb

require 'spec_helper'
require 'auth/database'
require 'auth/operations/customers/doctor'

RSpec.describe Auth::Operations::Customers::Doctor do
  let(:email) { 'live@example.com' }
  let(:issues)   { [] }
  let(:repaired) { [] }

  let(:customer) do
    double(
      'Customer',
      email: email,
      objid: 'obj_c',
      extid: 'ur_c',
      obscure_email: 'li***@e***.com',
      organization_instances: [],
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:le)
  end

  def doctor(repair: false)
    described_class.new(customer: customer, repair: repair, actor: 'cli')
  end

  # =========================================================================
  describe ':auth_email_drift' do
    let(:by_external_id) { double('by_external_id') }
    let(:by_id)          { double('by_id', update: 1) }
    let(:accounts)       { double('accounts') }
    let(:db)             { double('db') }

    before do
      allow(Auth::Database).to receive(:connection).and_return(db)
      allow(db).to receive(:[]).with(:accounts).and_return(accounts)
      allow(db).to receive(:transaction) { |&blk| blk.call }
      allow(accounts).to receive(:where).with(external_id: 'ur_c').and_return(by_external_id)
      allow(accounts).to receive(:where).with(id: 42).and_return(by_id)
      allow(by_external_id).to receive(:select).with(:id, :email).and_return(by_external_id)
    end

    def run(repair: false)
      doctor(repair: repair).send(:check_auth_email_drift, issues, repaired)
    end

    it 'reports nothing when the accounts row agrees with the Customer' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: email })

      run

      expect(issues).to be_empty
    end

    it 'ignores case, matching the citext column' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: 'LIVE@Example.com' })

      run

      expect(issues).to be_empty
    end

    it 'reports a critical, repairable issue when the two stores disagree' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: 'stale@example.com' })

      run

      expect(issues.size).to eq(1)
      expect(issues.first[:check]).to eq(:auth_email_drift)
      expect(issues.first[:severity]).to eq(:critical)
      expect(issues.first[:repairable]).to be true
    end

    it 'obscures both addresses in the reported message' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: 'stale@example.com' })

      run

      expect(issues.first[:message]).not_to include('stale@example.com')
      expect(issues.first[:message]).not_to include(email)
    end

    it 'repairs Redis -> SQL only: the Customer address is written into accounts' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: 'stale@example.com' })

      run(repair: true)

      expect(by_id).to have_received(:update).with(hash_including(email: email))
      expect(repaired).to eq([{ customer: 'ur_c', action: :auth_email_drift_repaired }])
    end

    it 'does not write anything on an audit-only run' do
      allow(by_external_id).to receive(:first).and_return({ id: 42, email: 'stale@example.com' })

      run

      expect(by_id).not_to have_received(:update)
      expect(repaired).to be_empty
    end

    # A missing row is a provisioning gap owned by `customers sync-auth-accounts`,
    # not drift.
    it 'stays silent when there is no accounts row at all' do
      allow(by_external_id).to receive(:first).and_return(nil)

      run

      expect(issues).to be_empty
    end

    it 'is skipped entirely in simple mode (no auth database)' do
      allow(Auth::Database).to receive(:connection).and_return(nil)

      run

      expect(issues).to be_empty
    end

    it 'never aborts the sweep when the auth database is unreachable' do
      allow(by_external_id).to receive(:first).and_raise(StandardError, 'db down')

      expect { run }.not_to raise_error
      expect(issues).to be_empty
    end
  end

  # =========================================================================
  describe ':org_email_index_stale' do
    let(:org_index) { double('org.email_index') }
    let(:org)       { double('Organization', extid: 'og_a', email_index: org_index) }

    before do
      allow(Auth::Database).to receive(:connection).and_return(nil)
      allow(customer).to receive(:organization_instances).and_return([org])
    end

    def run(repair: false)
      doctor(repair: repair).send(:check_org_email_index, issues, repaired)
    end

    it 'reports nothing when the org index is correct and has no stale keys' do
      allow(org_index).to receive(:get).with(email).and_return('obj_c')
      allow(org_index).to receive(:hgetall).and_return({ email => 'obj_c' })

      run

      expect(issues).to be_empty
    end

    # The post-email-change signature: old key still points here, new key absent.
    it 'reports and repairs a missing entry alongside a stale one' do
      allow(org_index).to receive(:get).with(email).and_return(nil)
      allow(org_index).to receive(:hgetall).and_return({ 'old@example.com' => 'obj_c' })
      allow(org_index).to receive(:[]=)
      allow(org_index).to receive(:remove_field)

      run(repair: true)

      expect(issues.first[:check]).to eq(:org_email_index_stale)
      expect(issues.first[:repairable]).to be true
      expect(org_index).to have_received(:[]=).with(email, 'obj_c')
      expect(org_index).to have_received(:remove_field).with('old@example.com')
      expect(repaired.first).to include(action: :org_email_index_rekeyed, org: 'og_a', stale_keys: 1)
    end

    it 'reports a stale key even when the correct entry already exists' do
      allow(org_index).to receive(:get).with(email).and_return('obj_c')
      allow(org_index).to receive(:hgetall).and_return({ email => 'obj_c', 'old@example.com' => 'obj_c' })

      run

      expect(issues.size).to eq(1)
      expect(issues.first[:stale_keys]).to eq(1)
    end

    # Overwriting would STEAL the other customer's entry.
    it 'refuses to repair an entry held by a different customer' do
      allow(org_index).to receive(:get).with(email).and_return('obj_other')
      allow(org_index).to receive(:hgetall).and_return({})
      allow(org_index).to receive(:[]=)

      run(repair: true)

      expect(issues.first[:repairable]).to be false
      expect(org_index).not_to have_received(:[]=)
      expect(repaired).to be_empty
    end

    it 'does not write anything on an audit-only run' do
      allow(org_index).to receive(:get).with(email).and_return(nil)
      allow(org_index).to receive(:hgetall).and_return({ 'old@example.com' => 'obj_c' })
      allow(org_index).to receive(:[]=)
      allow(org_index).to receive(:remove_field)

      run

      expect(org_index).not_to have_received(:[]=)
      expect(org_index).not_to have_received(:remove_field)
    end
  end

  # =========================================================================
  describe ':org_contact_email_stale' do
    let(:stale_contact) { 'old@example.com' }
    let(:customer_email_index)  { double('Customer.email_index', get: nil) }
    let(:org_contact_email_index) { double('Organization.contact_email_index', get: nil) }

    let(:org) do
      instance = double(
        'Organization',
        extid: 'og_d',
        identifier: 'og_d',
        is_default: 'true',
        contact_email: stale_contact,
      )
      allow(instance).to receive(:owner?).with(customer).and_return(true)
      allow(instance).to receive(:contact_email=)
      allow(instance).to receive(:update_in_class_contact_email_index)
      allow(instance).to receive(:save)
      instance
    end

    before do
      allow(Auth::Database).to receive(:connection).and_return(nil)
      allow(customer).to receive(:organization_instances).and_return([org])
      allow(Onetime::Customer).to receive(:email_index).and_return(customer_email_index)
      allow(Onetime::Organization).to receive(:contact_email_index).and_return(org_contact_email_index)
    end

    def run(repair: false)
      doctor(repair: repair).send(:check_org_contact_email, issues, repaired)
    end

    it 'reports a default workspace whose contact address belongs to no account' do
      run

      expect(issues.size).to eq(1)
      expect(issues.first[:check]).to eq(:org_contact_email_stale)
      expect(issues.first[:severity]).to eq(:warning)
      expect(issues.first[:repairable]).to be true
    end

    it 'repairs by pointing contact_email at the customer address and re-keying the index' do
      run(repair: true)

      expect(org).to have_received(:contact_email=).with(email)
      expect(org).to have_received(:update_in_class_contact_email_index).with(stale_contact)
      expect(org).to have_received(:save)
      expect(repaired.first).to include(action: :org_contact_email_updated, org: 'og_d')
    end

    it 'leaves a contact deliberately set to another live account alone' do
      allow(customer_email_index).to receive(:get).with(stale_contact).and_return('obj_colleague')

      run

      expect(issues).to be_empty
    end

    it 'never touches a SHARED (non-default) organization' do
      allow(org).to receive(:is_default).and_return('false')

      run

      expect(issues).to be_empty
      expect(org).not_to have_received(:contact_email=)
    end

    it 'never touches an org the customer does not own' do
      allow(org).to receive(:owner?).with(customer).and_return(false)

      run

      expect(issues).to be_empty
    end

    it 'reports but refuses to repair when another org already holds the customer address' do
      allow(org_contact_email_index).to receive(:get).with(email).and_return('og_other')

      run(repair: true)

      expect(issues.first[:repairable]).to be false
      expect(org).not_to have_received(:contact_email=)
      expect(repaired).to be_empty
    end

    it 'does not write anything on an audit-only run' do
      run

      expect(org).not_to have_received(:contact_email=)
      expect(org).not_to have_received(:save)
    end
  end

  # =========================================================================
  # Failure auditing. The doctor deliberately does NOT use the audit_failures
  # macro: the macro records unconditionally, and this op's DEFAULT mode is a
  # pure diagnostic read that must never write an audit event (CONTRACT 4).
  # The gate is the same one the success event uses — a repair run with a
  # known actor — so these two tests are the contract.
  describe 'failure auditing (gated on the repair path)' do
    before do
      allow(Onetime::ColonelAuditEvent).to receive(:record)
      # Blow up in the FIRST check so the raise is deterministic regardless of
      # which checks the customer double happens to satisfy.
      allow(customer).to receive(:default_org_id).and_raise(Onetime::Problem, 'redis down')
    end

    it 'records ONE result: :failure event on a --repair run, and re-raises' do
      expect { doctor(repair: true).call }.to raise_error(Onetime::Problem, /redis down/)

      expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
        hash_including(
          actor: 'cli',
          verb: 'customer.doctor_repair',
          target: 'ur_c',
          result: :failure,
          detail: hash_including(error: 'Onetime::Problem', message: 'redis down'),
        ),
      )
    end

    # A `--all` sweep runs this op per customer. If a diagnostic failure wrote
    # an event, one broken datastore would emit up to MAX_EVENTS of them and
    # evict the real destructive-action trail from the count-capped set.
    it 'records NOTHING on a diagnostic run, even though it raises the same way' do
      expect { doctor(repair: false).call }.to raise_error(Onetime::Problem, /redis down/)

      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end
