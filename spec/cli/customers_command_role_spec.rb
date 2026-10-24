# spec/cli/customers_command_role_spec.rb
#
# frozen_string_literal: true

# `bin/ots customers role promote|demote` and `bin/ots customers unverify`
# against the #4328 interlocks.
#
# The CLI is the DOCUMENTED recovery path out of a last-colonel lockout: the
# HTTP endpoints refuse a colonel demoting or unverifying themselves, and tell
# the operator to use these commands instead. That makes it the one adapter
# whose refusal handling has to be verified rather than assumed — a command that
# printed "colonel -> customer" and exited 0 while the op refused would send an
# operator away believing they had done something they had not.
#
# The interlocks themselves live in the shared ops and are unit-tested there
# (apps/web/auth/spec/operations/customers/{set_role,set_verification}_spec.rb);
# these examples own only the CLI's contract: message + exit status.
#
# The last groups pin the flag boundary between promote/demote (y/N prompt, no
# write gate) and the `role reconcile` subcommand (write gate): a gate flag
# promote or demote would ignore must be refused, not accepted.
#
# Run: bundle exec rspec spec/cli/customers_command_role_spec.rb

require_relative 'cli_spec_helper'

require 'auth/operations/customers/set_role'
require 'auth/operations/customers/reconcile_role_index'
require 'auth/operations/customers/set_verification'
require 'auth/operations/set_customer_verification'

RSpec.describe 'Customers Role Command interlocks', type: :cli do
  let(:customer) do
    double('Customer',
      email: 'colonel@example.com', objid: 'cust_col', extid: 'ur_col',
      role: 'colonel', verified?: true, anonymous?: false)
  end

  before do
    allow(Onetime::Customer).to receive(:email_exists?).and_return(true)
    allow(Onetime::Customer).to receive(:find_by_email).and_return(customer)
  end

  def stub_set_role(status)
    result = instance_double(Auth::Operations::Customers::SetRole::Result, status: status)
    allow(Auth::Operations::Customers::SetRole).to receive(:new).and_return(
      instance_double(Auth::Operations::Customers::SetRole, call: result),
    )
  end

  describe 'role demote' do
    it 'prints the refusal and exits non-zero for the last remaining colonel' do
      stub_set_role(:last_colonel)

      output = run_cli_command_quietly('customers', 'role', 'demote', 'colonel@example.com', '--force')

      expect(output[:stdout]).to include('last remaining verified colonel')
      expect(output[:stdout]).to include('bin/ots customers role promote')
      expect(output[:stdout]).not_to include('-> customer')
      expect(last_exit_code).to eq(1)
    end

    it 'succeeds and exits zero for a colonel who is not the last one' do
      stub_set_role(:success)

      output = run_cli_command_quietly('customers', 'role', 'demote', 'colonel@example.com', '--force')

      expect(output[:stdout]).to match(/-> customer/)
      expect(last_exit_code).to eq(0)
    end

    it 'exits non-zero on a status it does not recognize' do
      stub_set_role(:something_new)

      output = run_cli_command_quietly('customers', 'role', 'demote', 'colonel@example.com', '--force')

      expect(output[:stdout]).to include('did not complete')
      expect(last_exit_code).to eq(1)
    end
  end

  # `promote --role admin` on a colonel is a DEMOTION in effect, so it reaches
  # the same interlock.
  describe 'role promote' do
    it 'refuses a sideways move that would demote the last colonel' do
      stub_set_role(:last_colonel)

      output = run_cli_command_quietly(
        'customers', 'role', 'promote', 'colonel@example.com', '--role', 'admin', '--force'
      )

      expect(output[:stdout]).to include('last remaining verified colonel')
      expect(last_exit_code).to eq(1)
    end

    it 'still promotes normally' do
      stub_set_role(:success)

      output = run_cli_command_quietly(
        'customers', 'role', 'promote', 'colonel@example.com', '--role', 'admin', '--force'
      )

      expect(output[:stdout]).to include('-> admin')
      expect(last_exit_code).to eq(0)
    end
  end

  describe 'role promote/demote and the write-gate flags' do
    before { allow($stdin).to receive(:gets).and_return("y\n") }

    # Before reconcile became its own subcommand, the gate declared --dry-run
    # on the whole command and `demote EMAIL --dry-run --force` demoted.
    it 'refuses --dry-run on demote without writing' do
      stub_set_role(:success)

      run_cli_command_quietly('customers', 'role', 'demote', 'colonel@example.com', '--dry-run', '--force')

      expect(Auth::Operations::Customers::SetRole).not_to have_received(:new)
      expect(last_exit_code).to eq(1)
    end

    it 'refuses --dry-run on promote without writing' do
      stub_set_role(:success)

      run_cli_command_quietly('customers', 'role', 'promote', 'colonel@example.com',
        '--role', 'admin', '--dry-run', '--force')

      expect(Auth::Operations::Customers::SetRole).not_to have_received(:new)
      expect(last_exit_code).to eq(1)
    end

    ['--apply', '--yes', '-y'].each do |flag|
      it "refuses #{flag} on promote instead of reaching the prompt" do
        stub_set_role(:success)

        run_cli_command_quietly('customers', 'role', 'promote', 'colonel@example.com', '--role', 'admin', flag)

        expect($stdin).not_to have_received(:gets)
        expect(Auth::Operations::Customers::SetRole).not_to have_received(:new)
        expect(last_exit_code).to eq(1)
      end
    end
  end

  describe 'role reconcile subcommand' do
    def stub_reconcile
      allow(Auth::Operations::Customers::ReconcileRoleIndex).to receive(:new) do |apply:, **|
        result = Auth::Operations::Customers::ReconcileRoleIndex::Result.new(
          status: :clean, scanned: 0, buckets: {}, additions: [], removals: [], skipped: [], dry_run: !apply,
        )
        instance_double(Auth::Operations::Customers::ReconcileRoleIndex, call: result)
      end
    end

    before { stub_reconcile }

    it 'is a dry run by default' do
      output = run_cli_command_quietly('customers', 'role', 'reconcile')

      expect(Auth::Operations::Customers::ReconcileRoleIndex).to have_received(:new)
        .with(hash_including(apply: false))
      expect(output[:stdout]).to include('DRY RUN — nothing was written')
      expect(last_exit_code).to eq(0)
    end

    ['--apply', '--yes', '-y'].each do |flag|
      it "repairs with #{flag}" do
        run_cli_command_quietly('customers', 'role', 'reconcile', flag)

        expect(Auth::Operations::Customers::ReconcileRoleIndex).to have_received(:new)
          .with(hash_including(apply: true))
        expect(last_exit_code).to eq(0)
      end
    end

    it 'still repairs with the former --apply --force spelling' do
      run_cli_command_quietly('customers', 'role', 'reconcile', '--apply', '--force')

      expect(Auth::Operations::Customers::ReconcileRoleIndex).to have_received(:new)
        .with(hash_including(apply: true))
      expect(last_exit_code).to eq(0)
    end

    # --force/-f only skipped the prompt that --apply also needed, so a bare
    # --force was a dry run before the gate. It must not become a write.
    ['--force', '-f'].each do |flag|
      it "stays a dry run with a bare #{flag}" do
        run_cli_command_quietly('customers', 'role', 'reconcile', flag)

        expect(Auth::Operations::Customers::ReconcileRoleIndex).to have_received(:new)
          .with(hash_including(apply: false))
        expect(last_exit_code).to eq(0)
      end
    end
  end

  describe 'unverify' do
    def stub_set_verification(result)
      allow(Auth::Operations::Customers::SetVerification).to receive(:new).and_return(
        instance_double(Auth::Operations::Customers::SetVerification, call: result),
      )
    end

    before do
      allow(Onetime::Customer).to receive(:load_by_extid_or_email).and_return(customer)
      allow(Onetime::Customer).to receive(:load).and_return(customer)
    end

    it 'prints the refusal and exits non-zero for the last verified colonel' do
      stub_set_verification(:last_colonel)

      output = run_cli_command_quietly('customers', 'unverify', 'colonel@example.com')

      expect(output[:stdout]).to include('last remaining verified colonel')
      expect(output[:stdout]).not_to include('Unverified:')
      expect(last_exit_code).to eq(1)
    end

    it 'succeeds and exits zero otherwise' do
      stub_set_verification(:success)

      output = run_cli_command_quietly('customers', 'unverify', 'colonel@example.com')

      expect(output[:stdout]).to include('Unverified:')
      expect(last_exit_code).to eq(0)
    end
  end
end
