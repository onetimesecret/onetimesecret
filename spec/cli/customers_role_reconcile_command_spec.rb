# spec/cli/customers_role_reconcile_command_spec.rb
#
# frozen_string_literal: true

# Covers `bin/ots customers role reconcile` (#3974): the dry-run default
# reports role-index drift without writing, and an applied run repairs the
# index with targeted SADD/SREM (never rebuild's DEL-then-repopulate).
#
# Drift fixtures reproduce the REAL familia-2.12 mechanisms:
#   * stale-bucket drift — a role change persisted through a targeted writer
#     (save_fields routes multi_index maintenance through the ADD-ONLY
#     add_to_class_role_index, retaining the previous value's bucket member)
#   * expired-hash drift — the customer hash TTL-expired (right_to_be_forgotten
#     sets default_expiration = 365.days) while its role_index member persists
#   * missing-member drift — the index simply lacks a live customer's entry
#
# Lives in its own file with a REAL datastore (same rationale as
# spec/cli/org_doctor_command_spec.rb): the reconcile walks Customer.instances
# and SCANs customer:role_index:*, which the mocked `type: :cli` lane satisfies
# vacuously. The examples drive the command's private reconcile_role_index
# (via #send) instead of the full CLI `call` — the reconcile semantics are the
# unit under test; argument parsing and boot are covered elsewhere.
#
# Run: bundle exec rspec spec/cli/customers_role_reconcile_command_spec.rb

require_relative 'cli_spec_helper'
require 'stringio'

RSpec.describe 'Customers Role Reconcile Command' do
  describe 'real datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
    let(:command) { Onetime::CLI::CustomersRoleCommand.new }

    def colonel_bucket
      Onetime::Customer.role_index_for('colonel')
    end

    def customer_bucket
      Onetime::Customer.role_index_for('customer')
    end

    before do
      @customers = []
      # Converge to a clean baseline first, so residue from other spec files
      # (customers created without index entries, expired fixtures) cannot
      # bleed drift into these examples' expectations.
      Auth::Operations::Customers::ReconcileRoleIndex.new(apply: true).call
    end

    after do
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[role reconcile spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
      # Drop any index members the examples seeded for customers that no
      # longer exist (destroy! only clears the CURRENT role's bucket).
      # Rescued because the failure-handling example's stub on the op class is
      # still active while after-hooks run.
      begin
        Auth::Operations::Customers::ReconcileRoleIndex.new(apply: true).call
      rescue StandardError => ex
        warn "[role reconcile spec] index cleanup skipped: #{ex.class}: #{ex.message}"
      end
    end

    def create_customer(email, role: 'customer')
      cust      = Onetime::Customer.create!(email: email)
      cust.role = role
      cust.save
      @customers << cust
      cust
    end

    # Runs the command's private reconcile with stdout captured, converting a
    # SystemExit into its status so exit-code expectations read directly.
    # @return [Hash] { stdout:, exit_code: } (exit_code 0 when no exit raised)
    def run_reconcile(apply: false, force: false, json: false)
      original = $stdout
      $stdout  = StringIO.new
      code     = 0
      begin
        command.send(:reconcile_role_index, apply: apply, force: force, json: json)
      rescue SystemExit => ex
        code = ex.status
      ensure
        captured = $stdout.string
        $stdout  = original
      end
      { stdout: captured, exit_code: code }
    end

    describe 'dry run (default)' do
      it 'exits 0 and reports clean when the index matches the role fields' do
        create_customer("clean_#{suffix}@onetimesecret.com", role: 'colonel')

        outcome = run_reconcile

        expect(outcome[:exit_code]).to eq(0)
        expect(outcome[:stdout]).to include('DRY RUN')
        expect(outcome[:stdout]).to include('Status:            clean')
      end

      it 'reports stale-bucket drift from a targeted-writer role change WITHOUT writing' do
        # Reproduce mechanism 1: save_fields persists the new role but the
        # multi_index maintenance is add-only, so the customer now occupies
        # BOTH buckets.
        drifted      = create_customer("drift_#{suffix}@onetimesecret.com", role: 'customer')
        drifted.role = 'colonel'
        drifted.save_fields(:role)

        expect(colonel_bucket.member?(drifted.objid)).to be(true)
        expect(customer_bucket.member?(drifted.objid)).to be(true) # the stale bucket

        outcome = run_reconcile

        # Drift found on a dry run is a non-zero exit (doctor precedent).
        expect(outcome[:exit_code]).to eq(1)
        expect(outcome[:stdout]).to include('DRY RUN')
        expect(outcome[:stdout]).to include("Would remove #{drifted.objid} from role_index:customer")

        # Nothing was written: the stale member is still there.
        expect(customer_bucket.member?(drifted.objid)).to be(true)
      end

      it 'reports an expired-hash member and a missing member without writing' do
        # Mechanism 2: the customer hash expired (RTBF TTL) but the index
        # member persists. Simulated by deleting the hash while leaving the
        # instances entry and index member in place, exactly what EXPIRE does.
        expired = create_customer("expired_#{suffix}@onetimesecret.com", role: 'colonel')
        Familia.dbclient.del(expired.dbkey)

        # Missing member: a live colonel the index lost.
        lost = create_customer("lost_#{suffix}@onetimesecret.com", role: 'colonel')
        colonel_bucket.remove_element(lost.objid)

        outcome = run_reconcile

        expect(outcome[:exit_code]).to eq(1)
        expect(outcome[:stdout]).to include("Would remove #{expired.objid} from role_index:colonel")
        expect(outcome[:stdout]).to include("Would add #{lost.objid} to role_index:colonel")

        expect(colonel_bucket.member?(expired.objid)).to be(true)
        expect(colonel_bucket.member?(lost.objid)).to be(false)
      end
    end

    describe 'applied run' do
      it 'repairs stale and missing members incrementally and exits 0' do
        drifted      = create_customer("apply_drift_#{suffix}@onetimesecret.com", role: 'customer')
        drifted.role = 'colonel'
        drifted.save_fields(:role)

        lost = create_customer("apply_lost_#{suffix}@onetimesecret.com", role: 'colonel')
        colonel_bucket.remove_element(lost.objid)

        # Untouched bystander proves the repair is targeted SREM/SADD, not a
        # DEL-then-repopulate of the whole bucket.
        steady = create_customer("apply_steady_#{suffix}@onetimesecret.com", role: 'colonel')

        outcome = run_reconcile(apply: true, force: true)

        expect(outcome[:exit_code]).to eq(0)
        expect(outcome[:stdout]).to include('repaired')
        expect(outcome[:stdout]).not_to include('DRY RUN')

        expect(customer_bucket.member?(drifted.objid)).to be(false)
        expect(colonel_bucket.member?(drifted.objid)).to be(true)
        expect(colonel_bucket.member?(lost.objid)).to be(true)
        expect(colonel_bucket.member?(steady.objid)).to be(true)

        # Idempotent: a follow-up dry run is clean.
        expect(run_reconcile[:exit_code]).to eq(0)
      end

      it 'refuses a scripted --json apply without --force' do
        outcome = run_reconcile(apply: true, force: false, json: true)

        expect(outcome[:exit_code]).to eq(1)
        expect(outcome[:stdout]).to include('Refusing to apply without --force in --json mode')
      end

      it 'emits machine-readable JSON with --json' do
        lost = create_customer("json_lost_#{suffix}@onetimesecret.com", role: 'colonel')
        colonel_bucket.remove_element(lost.objid)

        outcome = run_reconcile(apply: true, force: true, json: true)
        payload = JSON.parse(outcome[:stdout])

        expect(outcome[:exit_code]).to eq(0)
        expect(payload['status']).to eq('repaired')
        expect(payload['dry_run']).to be(false)
        expect(payload['additions']).to include('role' => 'colonel', 'objid' => lost.objid)
      end
    end

    describe 'failure handling' do
      it 'exits 1 when the reconcile op raises' do
        allow(Auth::Operations::Customers::ReconcileRoleIndex)
          .to receive(:new).and_raise(RuntimeError, 'datastore unavailable')

        outcome = run_reconcile

        expect(outcome[:exit_code]).to eq(1)
        expect(outcome[:stdout]).to include('reconcile failed')
      end
    end

    describe 'op-level behavior' do
      it 'dry run returns :drift with per-bucket counts and writes nothing' do
        drifted      = create_customer("op_drift_#{suffix}@onetimesecret.com", role: 'customer')
        drifted.role = 'colonel'
        drifted.save_fields(:role)

        result = Auth::Operations::Customers::ReconcileRoleIndex.new.call

        expect(result.status).to eq(:drift)
        expect(result.dry_run).to be(true)
        expect(result.removals).to include(role: 'customer', objid: drifted.objid)
        expect(result.buckets['customer'][:stale]).to be >= 1
        expect(customer_bucket.member?(drifted.objid)).to be(true)
      end

      it 'applied run returns :repaired and converges to :clean' do
        drifted      = create_customer("op_apply_#{suffix}@onetimesecret.com", role: 'customer')
        drifted.role = 'colonel'
        drifted.save_fields(:role)

        applied = Auth::Operations::Customers::ReconcileRoleIndex.new(apply: true).call
        expect(applied.status).to eq(:repaired)
        expect(customer_bucket.member?(drifted.objid)).to be(false)

        second = Auth::Operations::Customers::ReconcileRoleIndex.new(apply: true).call
        expect(second.status).to eq(:clean)
      end
    end
  end
end
